///|
/// Typed failure classes for PDF parsing and page-tree construction.
pub suberror PdfError {
  PdfError(String)
}

///|
/// A PDF stream object: its dictionary plus decoded (or still encoded) bytes.
pub struct PdfStream {
  dict : Array[(String, PdfValue)]
  data : Bytes
}

///|
/// A PDF object. Dictionaries keep insertion order and use linear lookup:
/// page/resource dictionaries are small, and order is useful for diagnostics.
pub enum PdfValue {
  Null
  Bool(Bool)
  Int(Int32)
  Real(Double)
  Str(Bytes)
  Name(String)
  Array(Array[PdfValue])
  Dict(Array[(String, PdfValue)])
  Ref(Int32, Int32)
  Stream(PdfStream)
}

///|
pub fn PdfValue::type_name(self : PdfValue) -> String {
  match self {
    Null => "null"
    Bool(_) => "bool"
    Int(_) => "int"
    Real(_) => "real"
    Str(_) => "string"
    Name(_) => "name"
    Array(_) => "array"
    Dict(_) => "dict"
    Ref(_, _) => "ref"
    Stream(_) => "stream"
  }
}

///|
pub fn PdfValue::as_dict(self : PdfValue) -> Array[(String, PdfValue)]? {
  match self {
    Dict(d) => Some(d)
    Stream(s) => Some(s.dict)
    _ => None
  }
}

///|
pub fn PdfValue::as_array(self : PdfValue) -> Array[PdfValue]? {
  match self {
    Array(a) => Some(a)
    _ => None
  }
}

///|
pub fn PdfValue::as_number(self : PdfValue) -> Double? {
  match self {
    Int(i) => Some(i.to_double())
    Real(r) => Some(r)
    _ => None
  }
}

///|
pub fn PdfValue::as_int(self : PdfValue) -> Int32? {
  match self {
    Int(i) => Some(i)
    Real(r) => {
      let i = r.to_int()
      if i.to_double() == r {
        Some(i)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
pub fn PdfValue::as_name(self : PdfValue) -> String? {
  match self {
    Name(n) => Some(n)
    _ => None
  }
}

///|
pub fn dict_get(dict : Array[(String, PdfValue)], key : String) -> PdfValue? {
  for entry in dict {
    if entry.0 == key {
      return Some(entry.1)
    }
  }
  None
}

///|
/// One page reduced to what a renderer needs: a box and decoded content
/// streams, plus the page's (inherited) resource dictionary.
pub struct PdfPage {
  width : Double
  height : Double
  contents : Array[Bytes]
  resources : Array[(String, PdfValue)]
}

///|
pub struct PdfDocument {
  version : String
  objects : Array[PdfValue?]
  pages : Array[PdfPage]
}

///|
pub fn PdfDocument::page_count(self : PdfDocument) -> Int32 {
  self.pages.length()
}

///|
pub fn PdfDocument::page(self : PdfDocument, index : Int32) -> PdfPage? {
  self.pages.get(index)
}

///|
/// Resolve indirect references against the document object table.
pub fn PdfDocument::resolve(self : PdfDocument, value : PdfValue) -> PdfValue {
  match value {
    Ref(num, _) =>
      match self.objects.get(num) {
        Some(Some(v)) => v
        _ => Null
      }
    _ => value
  }
}

///|
pub fn PdfDocument::resolve_dict(
  self : PdfDocument,
  value : PdfValue,
) -> Array[(String, PdfValue)] {
  match self.resolve(value).as_dict() {
    Some(d) => d
    None => []
  }
}
