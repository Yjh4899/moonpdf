# Incremental updates

## Why this matters

Incremental saving is the normal way PDF editors, signing tools and review
workflows append a revision without rewriting the file. A revised page can point
at objects from an older revision: a Form XObject logo, a font, an images
dictionary or an entire content stream. A reader that only follows the newest
`startxref` offset and ignores `/Prev` will silently render the wrong page or
fail to find the new content. Incremental updates are therefore part of the
required file-structure target (ISO 32000-1, 7.5.6), not an optional feature.

## Parsing algorithm

1. **Find the newest cross-reference section.** Read the last `startxref` and
   jump to that offset. The section may be a classic `xref` table or an xref
   stream (`/Type /XRef`).
2. **Follow `/Prev`.** Each revision's trailer points to the previous revision.
   Collect sections newest → oldest until `/Prev` is absent. Reject cycles and
   offsets ≤ 0.
3. **Handle hybrid files.** If a classic trailer has `/XRefStm`, parse that xref
   stream and merge its entries. Classic table entries take precedence over the
   supplemental stream entries (ISO 32000-1, 7.5.8.4).
4. **Merge entries oldest → newest.** Later revisions overwrite earlier entries
   for the same object number. A free entry (`f` or type 0) removes the object
   from the effective object map.
5. **Choose the effective trailer.** The newest trailer that contains `/Root`
   supplies the document catalog; `/Size` is the maximum object count seen.
6. **Load uncompressed objects.** For every type-1 entry, parse the indirect
   object at its byte offset and verify that the object number matches the xref.
7. **Load object streams.** For every type-2 entry, group by the container
   object number, decode the `/ObjStm` stream, read its `N` object-number/offset
   pairs, and parse each contained object. Object streams must not be nested
   (ISO 32000-1, 7.5.7).
8. **Walk the final page tree.** Resolve `/Root` → `/Pages` against the merged
   object map, inheriting `/MediaBox` and `/Resources`. Page content streams are
   decoded with their filters before rendering.

The implementation lives in [`pdf/document.mbt`](../pdf/document.mbt) and
[`pdf/filter.mbt`](../pdf/filter.mbt). Regression coverage is in
[`tests/integration`](../tests/integration).

## Fixture: reusing an old Form XObject

`fixtures/incremental-base.pdf` is the base revision:

- object 1: catalog; object 2: pages, with `/Resources 6 0 R`;
- object 3: page, `/Contents 4 0 R`;
- object 4: page content, only `/Logo Do`;
- object 5: font `/F1` (Helvetica);
- object 6: resource dictionary `/Font << /F1 5 0 R >> /XObject << /Logo 8 0 R >> >>`;
- object 8: Form XObject `/Logo` with `/BBox [0 0 300 200]`, drawing the blue
  header panel and the white text `MOONPDF BASE`.

`fixtures/incremental.pdf` appends a revision:

- rewrites **only object 3** to `/Contents [4 0 R 7 0 R]`;
- appends **object 7**, a new body stream (green panel + `REVISION TWO`);
- writes a second `xref` section for objects 3 and 7, with
  `/Prev <base startxref>` and the same `/Root`.

Object 4 (old content), object 6 (resource dictionary), object 5 (font) and
object 8 (Form XObject) are **not rewritten**. The expected page is therefore:

- the old blue header from the reused Form XObject, with `MOONPDF BASE`;
- the new green body from object 7, with `REVISION TWO`.

![Incremental update: reused logo form and new body](images/incremental.png)

The integration test asserts both regions by sampling the rendered pixels:
the header sample must be blue and the body sample must be green. A reader that
ignores `/Prev` cannot find object 7 and fails the body assertion; a reader that
ignores object inheritance cannot resolve the old `/Resources` and loses the
header.

## Related modern layout

`fixtures/xref-stream.pdf` covers the other common modern layout: the xref is a
Flate-compressed stream, the page and font objects live inside an object
stream, and the page content stream is Flate-compressed. Both fixtures are
rendered in CI, so the incremental path and the xref-stream/object-stream path
are exercised together.
