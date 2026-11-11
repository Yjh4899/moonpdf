///|
fn usage() -> Unit {
  println("MoonPDF - a pure-MoonBit PDF page renderer")
  println("")
  println("Usage:")
  println("  moonpdf <input.pdf> [output.png] [--page N] [--scale S]")
  println("")
  println("Options:")
  println("  --page N   1-based page number (default: 1)")
  println("  --scale S  output scale, 1.0 = 72 dpi (default: 1.0)")
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
  let mut i = 2
  while i < args.length() {
    let arg = args[i]
    if arg == "--page" && i + 1 < args.length() {
      page = parse_int_arg(args[i + 1], 1)
      i = i + 2
    } else if arg == "--scale" && i + 1 < args.length() {
      scale = parse_double_arg(args[i + 1], 1.0)
      i = i + 2
    } else if output == "" {
      output = arg
      i = i + 1
    } else {
      i = i + 1
    }
  }
  if output == "" {
    output = "\{input}.png"
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
  let pages = @lib.page_count(data) catch {
    @lib.MoonPdfError(msg) => {
      println("error: \{msg}")
      return
    }
  }
  if page > pages {
    println(
      "error: page \{page} does not exist (document has \{pages} page(s))",
    )
    return
  }
  let png = @lib.render_page_png(data, page - 1, scale) catch {
    _ => {
      println("error: failed to render page \{page}")
      return
    }
  }
  @fs.write_bytes_to_file(output, png) catch {
    _ => {
      println("error: cannot write \{output}")
      return
    }
  }
  println(
    "rendered page \{page}/\{pages} at scale \{scale} -> \{output} (\{png.length()} bytes)",
  )
}
