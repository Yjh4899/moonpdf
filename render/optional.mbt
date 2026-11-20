///|
/// Determine whether an optional-content reference is visible on the page.
fn optional_content_visible(page : @pdf.PdfPage, value : @pdf.PdfValue) -> Bool {
  match value {
    @pdf.Ref(number, _) => {
      let mut visible = true
      for hidden in page.oc_off {
        if hidden == number {
          visible = false
        }
      }
      visible
    }
    _ => true
  }
}

///|
/// Drop operations inside hidden `/OC` marked-content sections.
pub fn filter_optional_content(
  page : @pdf.PdfPage,
  ops : Array[@pdf.ContentOp],
) -> Array[@pdf.ContentOp] {
  let out : Array[@pdf.ContentOp] = Array(capacity=ops.length())
  let stack : Array[Bool] = []
  for op in ops {
    if op.op == "BDC" {
      let mut visible = true
      if op.operands.length() >= 2 {
        let tag = match op.operands[0].as_name() {
          Some(name) => name
          None => ""
        }
        if tag == "OC" {
          let mut property = op.operands[1]
          match property {
            @pdf.Name(name) => {
              let properties = match
                @pdf.dict_get(page.resources, "Properties") {
                Some(value) => page.resolve_dict(value)
                None => []
              }
              match @pdf.dict_get(properties, name) {
                Some(value) => property = value
                None => ()
              }
            }
            _ => ()
          }
          visible = optional_content_visible(page, property)
        }
      }
      stack.push(visible)
      out.push(op)
    } else if op.op == "BMC" {
      stack.push(true)
      out.push(op)
    } else if op.op == "EMC" {
      if stack.length() > 0 {
        ignore(stack.pop())
      }
      out.push(op)
    } else {
      let mut visible = true
      for item in stack {
        if !item {
          visible = false
        }
      }
      if visible {
        out.push(op)
      }
    }
  }
  out
}
