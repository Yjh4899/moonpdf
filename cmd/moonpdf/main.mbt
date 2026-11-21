///|
fn usage() -> Unit {
  println("MoonPDF - a pure-MoonBit PDF page renderer")
  println("")
  println("Usage:")
  println("  moonpdf <input.pdf> [output.png|output.svg] [options]")
  println("")
  println("Options:")
  println("  --page N      1-based page number (default: 1)")
  println("  --all         render every page")
  println("  --pages LIST  comma-separated pages/ranges, e.g. 1,3-5")
  println("  --out-dir D   output directory for --all/--pages (default: .)")
  println("  --scale S     output scale, 1.0 = 72 dpi (default: 1.0)")
  println("  --svg         write SVG (vector when possible, PNG fallback)")
}

///|
fn parse_int_arg(text : String, fallback : Int32) -> Int32 {
  @string.parse_int(text) catch {
    _ => fallback
  }
}

///|
fn parse_double_arg(text : String, fallback : Double) -> Double {
  @string.parse_double(text) catch {
    _ => fallback
  }
}

///|
fn pad3(value : Int32) -> String {
  if value < 10 {
    "00\{value}"
  } else if value < 100 {
    "0\{value}"
  } else {
    "\{value}"
  }
}

///|
fn parse_page_spec(spec : String, total : Int32) -> Array[Int32]? {
  let out : Array[Int32] = []
  for part in spec.split(",") {
    let text = part.to_owned()
    if text == "" {
      continue
    }
    let (start, end) = match text.split_once("-") {
      Some((left, right)) => {
        let a = @string.parse_int(left.to_owned()) catch {
          _ => {
            println("error: invalid --pages value: \{text}")
            return None
          }
        }
        let b = @string.parse_int(right.to_owned()) catch {
          _ => {
            println("error: invalid --pages value: \{text}")
            return None
          }
        }
        (a, b)
      }
      None => {
        let n = @string.parse_int(text) catch {
          _ => {
            println("error: invalid --pages value: \{text}")
            return None
          }
        }
        (n, n)
      }
    }
    if start < 1 || end < 1 || start > total || end > total || start > end {
      println("error: page range \{text} is outside 1..\{total}")
      return None
    }
    let mut page = start
    while page <= end {
      out.push(page - 1)
      page = page + 1
    }
  }
  if out.length() == 0 {
    println("error: --pages selected no pages")
    return None
  }
  Some(out)
}

///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    usage()
    return
  }
  if args[1] == "--help" || args[1] == "-h" {
    usage()
    return
  }
  let input = args[1]
  let mut output = ""
  let mut page = 1
  let mut scale = 1.0
  let mut svg = false
  let mut all = false
  let mut pages_spec = ""
  let mut out_dir = ""
  let mut i = 2
  while i < args.length() {
    let arg = args[i]
    if arg == "--page" && i + 1 < args.length() {
      page = parse_int_arg(args[i + 1], 1)
      i = i + 2
    } else if arg == "--scale" && i + 1 < args.length() {
      scale = parse_double_arg(args[i + 1], 1.0)
      i = i + 2
    } else if arg == "--pages" && i + 1 < args.length() {
      pages_spec = args[i + 1]
      i = i + 2
    } else if arg == "--out-dir" && i + 1 < args.length() {
      out_dir = args[i + 1]
      i = i + 2
    } else if arg == "--svg" {
      svg = true
      i = i + 1
    } else if arg == "--all" {
      all = true
      i = i + 1
    } else if output == "" {
      output = arg
      i = i + 1
    } else {
      i = i + 1
    }
  }
  if page < 1 {
    page = 1
  }
  let data = @fs.read_file_to_bytes(input) catch {
    _ => {
      println("error: cannot read \{input}")
      return
    }
  }
  let document = @lib.open(data) catch {
    @lib.MoonPdfError(msg) => {
      println("error: \{msg}")
      return
    }
  }
  let pages = document.page_count()
  let multi = all || pages_spec != ""
  let indices = if multi {
    if pages_spec != "" {
      match parse_page_spec(pages_spec, pages) {
        Some(selected) => selected
        None => return
      }
    } else {
      let selected : Array[Int32] = []
      let mut p = 0
      while p < pages {
        selected.push(p)
        p = p + 1
      }
      selected
    }
  } else {
    if page > pages {
      println(
        "error: page \{page} does not exist (document has \{pages} page(s))",
      )
      return
    }
    [page - 1]
  }
  let extension = if svg { "svg" } else { "png" }
  if multi {
    let target = if out_dir != "" {
      out_dir
    } else if output != "" {
      output
    } else {
      "."
    }
    @fs.create_dir(target) catch {
      _ => ()
    }
    let rendered = if svg {
      document.render_pages_svg(indices, scale) catch {
        @lib.MoonPdfError(msg) => {
          println("error: \{msg}")
          return
        }
      }
    } else {
      document.render_pages_png(indices, scale) catch {
        @lib.MoonPdfError(msg) => {
          println("error: \{msg}")
          return
        }
      }
    }
    let mut index = 0
    while index < rendered.length() {
      let name = "page-\{pad3(indices[index] + 1)}.\{extension}"
      let path = if target == "." { name } else { "\{target}/\{name}" }
      @fs.write_bytes_to_file(path, rendered[index]) catch {
        _ => {
          println("error: cannot write \{path}")
          return
        }
      }
      println(
        "rendered page \{indices[index] + 1}/\{pages} at scale \{scale} -> \{path} (\{rendered[index].length()} bytes)",
      )
      index = index + 1
    }
  } else {
    if output == "" {
      output = "\{input}.\{extension}"
    }
    let rendered = if svg {
      document.render_svg(indices[0], scale) catch {
        @lib.MoonPdfError(msg) => {
          println("error: \{msg}")
          return
        }
      }
    } else {
      document.render_png(indices[0], scale) catch {
        @lib.MoonPdfError(msg) => {
          println("error: \{msg}")
          return
        }
      }
    }
    @fs.write_bytes_to_file(output, rendered) catch {
      _ => {
        println("error: cannot write \{output}")
        return
      }
    }
    println(
      "rendered page \{indices[0] + 1}/\{pages} at scale \{scale} -> \{output} (\{rendered.length()} bytes)",
    )
  }
}
