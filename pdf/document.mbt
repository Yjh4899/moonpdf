///|
/// Cross-reference table: object number -> byte offset.
priv struct Xref {
  entries : Array[(Int32, Int32)]
  trailer : Array[(String, PdfValue)]
}

///|
fn parse_xref(data : Bytes) -> Xref raise PdfError {
  let marker = @utf8.encode("startxref")
  let idx = match data.rev_find(marker) {
    Some(i) => i
    None => raise PdfError("missing startxref")
  }
  let p = Parser::new(data)
  p.pos = idx + marker.length()
  let offset = match p.try_parse_int() {
    Some(o) => o
    None => raise PdfError("invalid startxref offset")
  }
  p.pos = offset
  p.skip_ws()
  if !p.consume("xref") {
    raise PdfError("xref streams are not supported yet")
  }
  let entries : Array[(Int32, Int32)] = Array(capacity=64)
  let mut trailer : Array[(String, PdfValue)] = []
  while true {
    p.skip_ws()
    if p.consume("trailer") {
      let value = p.parse_value()
      trailer = match value {
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
      let obj_offset = match p.try_parse_int() {
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
        entries.push((start + i, obj_offset))
      }
      i = i + 1
    }
  }
  { entries, trailer, }
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
fn collect_contents(doc : PdfDocument, value : PdfValue?) -> Array[Bytes] {
  let out : Array[Bytes] = []
  match value {
    None => out
    Some(v) =>
      match doc.resolve(v) {
        Stream(s) => {
          out.push(s.data)
          out
        }
        Array(items) => {
          for item in items {
            match doc.resolve(item) {
              Stream(s) => out.push(s.data)
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
      let page : PdfPage = { width, height, contents, resources, }
      doc.pages.push(page)
    }
  }
}

///|
/// Parse a complete PDF document: header, classic xref table, indirect
/// objects, and the page tree.
pub fn parse_document(data : Bytes) -> PdfDocument raise PdfError {
  let version = if data.length() >= 8 && data.at(0).to_int() == 37 {
    @utf8.decode_lossy(data.exact_view(start=0, end=8))
  } else {
    raise PdfError("not a PDF file: missing %PDF header")
  }
  let xref = parse_xref(data)
  let mut max_object = 0
  for entry in xref.entries {
    if entry.0 > max_object {
      max_object = entry.0
    }
  }
  let objects : Array[PdfValue?] = Array::make(max_object + 1, None)
  for entry in xref.entries {
    let (num, offset) = entry
    let (parsed_num, _, value) = parse_indirect_object(data, offset)
    if parsed_num != num {
      raise PdfError("xref points to object \{parsed_num}, expected \{num}")
    }
    objects[parsed_num] = Some(value)
  }
  let doc : PdfDocument = { version, objects, pages: [], }
  let root = match dict_get(xref.trailer, "Root") {
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
