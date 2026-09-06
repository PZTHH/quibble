# Design inspiration: Superwhisper

Quibble's interface owes a debt to [Superwhisper](https://superwhisper.com), which
worked out much of what a good macOS dictation app looks like before Quibble
existed. Studying it in 2026-09 shaped several decisions, and it is worth saying
so plainly rather than pretending the shape of this app was arrived at alone.

What it taught us, and where Quibble landed:

- **A broad sidebar over a dense toolbar.** Dictation has a handful of real
  surfaces — home, history, modes, vocabulary, models — and they read better as
  a calm list than as a crowded toolbar.
- **Keycaps belong on the home screen.** Showing the actual shortcut where you
  start dictating teaches it far better than a settings page does.
- **Modes as large scannable rows** with a clear marker for the active one,
  rather than a dropdown that hides which one is running.
- **Vocabulary as one wide add field above a sparse list,** with preferred
  spellings and explicit replacements visually distinct from each other.
- **The model library is a management surface, not the daily screen.** A
  searchable table with provider, comparative indicators, and storage belongs
  one step away from where you dictate, not in front of it.

Quibble diverges where its own priorities differ: local-first inference with no
hidden cloud fallback, a workflow model where each mode is an explicit ordered
pipeline, and accuracy and speed indicators that state what they actually
measure. The detailed observations, including the surfaces of other apps, are in
the [dictation UX research](../../../Benchmarks/DICTATION-UX-RESEARCH.md).

The screenshots behind that research stay on the machine that made them. They
are another product's interface, carry no redistribution permission, and are
excluded from source control. They are not Quibble artwork and are not bundled
with the app.
