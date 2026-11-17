///|
/// One cross-reference entry. `kind` is 0 for a free object, 1 for an object at
/// a byte offset, and 2 for an object stored in an object stream.
priv struct XrefEntry {
  kind : Int32
  offset : Int32
  stream_num : Int32
}

///|
/// One revision's cross-reference section. Sections are linked through `/Prev`;
/// the first section parsed is the newest revision.
priv struct XrefSection {
  entries : Array[(Int32, XrefEntry)]
  trailer : Array[(String, PdfValue)]
  prev : Int32?
  xref_stm : Int32?
}

///|
fn dict_int(dict : Array[(String, PdfValue)], key : String) -> Int32? {
  match dict_get(dict, key) {
    Some(value) =>
      match value {
        Int(n) => Some(n)
        _ => None
      }
    None => None
  }
}

///|
fn parse_classic_xref(p : Parser) -> XrefSection raise PdfError {
  if !p.consume("xref") {
    raise PdfError("expected xref")
  }
  let entries : Array[(Int32, XrefEntry)] = Array(capacity=64)
  let mut trailer : Array[(String, PdfValue)] = []
  while true {
    p.skip_ws()
    if p.consume("trailer") {
      trailer = match p.parse_value() {
        Dict(d) => d
        _ => raise PdfError("trailer is not a dictionary")
      }
      break
    }
    let start = match p.try_parse_int() {
      Some(s) => s
      None => raise PdfError("invalid xref subsection")
    }
    let count = match p.try_parse_int() {
      Some(c) => c
      None => raise PdfError("invalid xref subsection count")
    }
    let mut i = 0
    while i < count {
      let offset = match p.try_parse_int() {
        Some(o) => o
        None => raise PdfError("invalid xref entry offset")
      }
      let _gen = match p.try_parse_int() {
        Some(g) => g
        None => raise PdfError("invalid xref entry generation")
      }
      p.skip_ws()
      let kind = p.read_keyword()
      if kind == "n" {
        entries.push((start + i, { kind: 1, offset, stream_num: 0, }))
      } else if kind == "f" {
        entries.push((start + i, { kind: 0, offset, stream_num: 0, }))
      } else {
        raise PdfError("invalid xref entry type")
      }
      i = i + 1
    }
  }
  let prev = dict_int(trailer, "Prev")
  let xref_stm = dict_int(trailer, "XRefStm")
  { entries, trailer, prev, xref_stm, }
}

///|
fn read_xref_field(
  data : Bytes,
  pos : Int32,
  width : Int32,
) -> Int32 raise PdfError {
  let mut value = 0
  let mut i = 0
  while i < width {
    if pos + i >= data.length() {
      raise PdfError("truncated xref stream row")
    }
    value = (value << 8) | data.at(pos + i).to_int()
    i = i + 1
  }
  value
}

///|
fn parse_xref_stream_entries(
  data : Bytes,
  dict : Array[(String, PdfValue)],
) -> Array[(Int32, XrefEntry)] raise PdfError {
  let widths = match dict_get(dict, "W") {
    Some(Array(items)) => items
    _ => raise PdfError("xref stream has no /W array")
  }
  if widths.length() < 3 {
    raise PdfError("xref stream /W needs at least 3 entries")
  }
  let w0 = match widths[0].as_int() {
    Some(n) => n
    None => raise PdfError("invalid xref /W entry")
  }
  let w1 = match widths[1].as_int() {
    Some(n) => n
    None => raise PdfError("invalid xref /W entry")
  }
  let w2 = match widths[2].as_int() {
    Some(n) => n
    None => raise PdfError("invalid xref /W entry")
  }
  if w0 < 0 || w1 < 0 || w2 < 0 || w0 > 8 || w1 > 8 || w2 > 8 {
    raise PdfError("unsupported xref field width")
  }
  let row_len = w0 + w1 + w2
  if row_len == 0 {
    raise PdfError("empty xref stream row")
  }
  let size = match dict_int(dict, "Size") {
    Some(n) => n
    None => raise PdfError("xref stream has no /Size")
  }
  let index = match dict_get(dict, "Index") {
    Some(Array(items)) => items
    None => [Int(0), Int(size)]
    _ => raise PdfError("invalid xref /Index")
  }
  if index.length() % 2 != 0 {
    raise PdfError("xref /Index must contain pairs")
  }
  let entries : Array[(Int32, XrefEntry)] = Array(capacity=64)
  let mut row = 0
  let mut i = 0
  while i + 1 < index.length() {
    let start = match index[i].as_int() {
      Some(n) => n
      None => raise PdfError("invalid xref /Index start")
    }
    let count = match index[i + 1].as_int() {
      Some(n) => n
      None => raise PdfError("invalid xref /Index count")
    }
    let mut k = 0
    while k < count {
      let pos = row * row_len
      if pos + row_len > data.length() {
        raise PdfError("xref stream data is truncated")
      }
      let kind = if w0 == 0 { 1 } else { read_xref_field(data, pos, w0) }
      let field2 = read_xref_field(data, pos + w0, w1)
      let _field3 = read_xref_field(data, pos + w0 + w1, w2)
      let entry = if kind == 0 {
        { kind: 0, offset: field2, stream_num: 0, }
      } else if kind == 1 {
        { kind: 1, offset: field2, stream_num: 0, }
      } else if kind == 2 {
        { kind: 2, offset: 0, stream_num: field2, }
      } else {
        raise PdfError("invalid xref stream entry type \{kind}")
      }
      entries.push((start + k, entry))
      row = row + 1
      k = k + 1
    }
    i = i + 2
  }
  entries
}

///|
fn parse_xref_stream_section(
  data : Bytes,
  offset : Int32,
) -> XrefSection raise PdfError {
  let (_, _, value) = parse_indirect_object(data, offset)
  let stream = match value {
    Stream(s) => s
    _ => raise PdfError("xref stream object is not a stream")
  }
  let decoded = decode_stream(stream)
  let entries = parse_xref_stream_entries(decoded, stream.dict)
  let prev = dict_int(stream.dict, "Prev")
  { entries, trailer: stream.dict, prev, xref_stm: None, }
}

///|
fn upsert_entry(
  entries : Array[(Int32, XrefEntry)],
  num : Int32,
  entry : XrefEntry,
) -> Unit {
  let mut i = 0
  while i < entries.length() {
    if entries[i].0 == num {
      entries[i] = (num, entry)
      return
    }
    i = i + 1
  }
  entries.push((num, entry))
}

///|
fn parse_xref_section(
  data : Bytes,
  offset : Int32,
) -> XrefSection raise PdfError {
  let p = Parser::new(data)
  p.pos = offset
  p.skip_ws()
  if p.starts_with("xref") {
    let section = parse_classic_xref(p)
    match section.xref_stm {
      Some(stm_offset) => {
        let stream_section = parse_xref_stream_section(data, stm_offset)
        let merged : Array[(Int32, XrefEntry)] = stream_section.entries.copy()
        for entry in section.entries {
          upsert_entry(merged, entry.0, entry.1)
        }
        {
          entries: merged,
          trailer: section.trailer,
          prev: section.prev,
          xref_stm: section.xref_stm,
        }
      }
      None => section
    }
  } else {
    parse_xref_stream_section(data, offset)
  }
}

///|
fn parse_xref_chain(
  data : Bytes,
  start : Int32,
) -> Array[XrefSection] raise PdfError {
  let sections : Array[XrefSection] = []
  let visited : Array[Int32] = []
  let mut offset = start
  let mut steps = 0
  while steps < 64 {
    for seen in visited {
      if seen == offset {
        raise PdfError("cyclic /Prev chain")
      }
    }
    visited.push(offset)
    let section = parse_xref_section(data, offset)
    sections.push(section)
    match section.prev {
      Some(prev) =>
        if prev <= 0 {
          raise PdfError("invalid /Prev offset")
        } else {
          offset = prev
        }
      None => break
    }
    steps = steps + 1
  }
  if steps >= 64 {
    raise PdfError("too many incremental revisions")
  }
  sections
}

///|
fn find_startxref(data : Bytes) -> Int32 raise PdfError {
  let marker = @utf8.encode("startxref")
  let idx = match data.rev_find(marker) {
    Some(i) => i
    None => raise PdfError("missing startxref")
  }
  let p = Parser::new(data)
  p.pos = idx + marker.length()
  match p.try_parse_int() {
    Some(offset) => offset
    None => raise PdfError("invalid startxref offset")
  }
}

///|
fn ensure_object_slots(objects : Array[PdfValue?], size : Int32) -> Unit {
  while objects.length() < size {
    objects.push(None)
  }
}

///|
fn load_object_stream(
  objects : Array[PdfValue?],
  stream_num : Int32,
) -> Unit raise PdfError {
  let value = match objects.get(stream_num) {
    Some(Some(Stream(s))) => s
    _ => raise PdfError("object stream \{stream_num} is missing")
  }
  let data = decode_stream(value)
  let count = match dict_int(value.dict, "N") {
    Some(n) => n
    None => raise PdfError("object stream has no /N")
  }
  let first = match dict_int(value.dict, "First") {
    Some(n) => n
    None => raise PdfError("object stream has no /First")
  }
  let p = Parser::new(data)
  let pairs : Array[(Int32, Int32)] = Array(capacity=count)
  let mut i = 0
  while i < count {
    let num = match p.try_parse_int() {
      Some(n) => n
      None => raise PdfError("invalid object stream header")
    }
    let off = match p.try_parse_int() {
      Some(n) => n
      None => raise PdfError("invalid object stream header")
    }
    pairs.push((num, off))
    i = i + 1
  }
  for pair in pairs {
    let (num, off) = pair
    p.pos = first + off
    let value = p.parse_value()
    ensure_object_slots(objects, num + 1)
    objects[num] = Some(value)
  }
}

///|
fn load_objects(
  data : Bytes,
  sections : Array[XrefSection],
) -> (Array[PdfValue?], Array[(String, PdfValue)]) raise PdfError {
  let mut max_num = 0
  for section in sections {
    match dict_int(section.trailer, "Size") {
      Some(size) => if size > max_num { max_num = size }
      None => ()
    }
    for entry in section.entries {
      if entry.0 >= max_num {
        max_num = entry.0 + 1
      }
    }
  }
  let merged : Array[XrefEntry?] = Array::make(max_num, None)
  // Oldest revision first, so newer entries overwrite older ones.
  let mut s = sections.length() - 1
  while s >= 0 {
    for entry in sections[s].entries {
      let num = entry.0
      while merged.length() <= num {
        merged.push(None)
      }
      merged[num] = Some(entry.1)
    }
    s = s - 1
  }
  let objects : Array[PdfValue?] = Array::make(merged.length(), None)
  // Pass 1: objects stored at explicit byte offsets.
  let mut num = 0
  while num < merged.length() {
    match merged[num] {
      Some(entry) =>
        if entry.kind == 1 {
          let (parsed_num, _, value) = parse_indirect_object(data, entry.offset)
          if parsed_num != num {
            raise PdfError(
              "xref points to object \{parsed_num}, expected \{num}",
            )
          }
          objects[num] = Some(value)
        }
      None => ()
    }
    num = num + 1
  }
  // Pass 2: objects stored in object streams. Object streams themselves must
  // be uncompressed (PDF 32000-1, 7.5.7).
  let object_streams : Array[Int32] = []
  num = 0
  while num < merged.length() {
    match merged[num] {
      Some(entry) =>
        if entry.kind == 2 {
          let mut found = false
          for existing in object_streams {
            if existing == entry.stream_num {
              found = true
            }
          }
          if !found {
            object_streams.push(entry.stream_num)
          }
        }
      None => ()
    }
    num = num + 1
  }
  for stream_num in object_streams {
    load_object_stream(objects, stream_num)
  }
  let mut trailer : Array[(String, PdfValue)] = []
  for section in sections {
    match dict_get(section.trailer, "Root") {
      Some(_) => {
        trailer = section.trailer
        break
      }
      None => ()
    }
  }
  (objects, trailer)
}

///|
fn dict_numbers(doc : PdfDocument, value : PdfValue?) -> Array[Double]? {
  match value {
    Some(v) =>
      match doc.resolve(v).as_array() {
        Some(items) => {
          let out : Array[Double] = Array(capacity=items.length())
          for item in items {
            match doc.resolve(item).as_number() {
              Some(n) => out.push(n)
              None => return None
            }
          }
          Some(out)
        }
        None => None
      }
    None => None
  }
}

///|
fn collect_contents(
  doc : PdfDocument,
  value : PdfValue?,
) -> Array[Bytes] raise PdfError {
  let out : Array[Bytes] = []
  match value {
    None => out
    Some(v) =>
      match doc.resolve(v) {
        Stream(s) => {
          out.push(decode_stream(s))
          out
        }
        Array(items) => {
          for item in items {
            match doc.resolve(item) {
              Stream(s) => out.push(decode_stream(s))
              _ => ()
            }
          }
          out
        }
        _ => out
      }
  }
}

///|
fn walk_page_tree(
  doc : PdfDocument,
  node_value : PdfValue,
  inherited_resources : Array[(String, PdfValue)],
  inherited_media : Array[Double],
) -> Unit raise PdfError {
  let node = doc.resolve_dict(node_value)
  let resources = match dict_get(node, "Resources") {
    Some(r) => doc.resolve_dict(r)
    None => inherited_resources
  }
  let media = match dict_numbers(doc, dict_get(node, "MediaBox")) {
    Some(m) => m
    None => inherited_media
  }
  match dict_get(node, "Kids") {
    Some(kids_value) =>
      match doc.resolve(kids_value).as_array() {
        Some(kids) =>
          for kid in kids {
            walk_page_tree(doc, kid, resources, media)
          }
        None => raise PdfError("Pages node has no Kids array")
      }
    None => {
      if media.length() < 4 {
        raise PdfError("page has no usable MediaBox")
      }
      let x0 = media.at(0)
      let y0 = media.at(1)
      let x1 = media.at(2)
      let y1 = media.at(3)
      let width = if x1 > x0 { x1 - x0 } else { 612.0 }
      let height = if y1 > y0 { y1 - y0 } else { 792.0 }
      let contents = collect_contents(doc, dict_get(node, "Contents"))
      let page : PdfPage = {
        width,
        height,
        contents,
        resources,
        objects: doc.objects,
      }
      doc.pages.push(page)
    }
  }
}

///|
/// Parse a complete PDF document. Supports classic xref tables, xref streams,
/// hybrid files (`/XRefStm`), object streams, and incremental update chains
/// linked by `/Prev`.
pub fn parse_document(data : Bytes) -> PdfDocument raise PdfError {
  let version = if data.length() >= 8 && data.at(0).to_int() == 37 {
    @utf8.decode_lossy(data.exact_view(start=0, end=8))
  } else {
    raise PdfError("not a PDF file: missing %PDF header")
  }
  let start = find_startxref(data)
  let sections = parse_xref_chain(data, start)
  let (objects, trailer) = load_objects(data, sections)
  let doc : PdfDocument = { version, objects, pages: [], }
  let root = match dict_get(trailer, "Root") {
    Some(r) => doc.resolve_dict(r)
    None => raise PdfError("trailer has no Root")
  }
  let pages_value = match dict_get(root, "Pages") {
    Some(p) => p
    None => raise PdfError("catalog has no Pages")
  }
  walk_page_tree(doc, pages_value, [], [0.0, 0.0, 612.0, 792.0])
  doc
}
