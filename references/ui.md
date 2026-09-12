# Look like ATAK, and survive the next tap

A plugin that looks like ATAK is a plugin an operator can already use. A plugin
that invents its own dialect is one more thing to learn in a vehicle, in gloves,
at night.

## The context rule — this one kills ATAK

**Anything that opens a window is built with the MapView (Activity) context;
plugin resources are resolved through the plugin context.** An `AlertDialog` or
`Toast` built on the plugin context throws `BadTokenException` and takes ATAK
down with it.

```java
new AlertDialog.Builder(mapView.getContext())      // host context: opens a window
        .setTitle(pluginContext.getString(R.string.pick_a_thing))   // plugin context: resources
        .setSingleChoiceItems(labels, selected, listener)
        .show();
```

**Never use a Spinner.** Its dropdown is a `Dialog` built from the context that
inflated the view — on the plugin context that is the crash above. Use a button
showing the current value that opens an `AlertDialog` with
`setSingleChoiceItems(...)`. For pickers with a handful of options, a compact
grid of dark buttons reads better than a full-screen list.

## Controls

- **Use ATAK's own button drawables** (`btn_gray`, copied out of the SDK
  template) and one button style everywhere —
  `templates/plugin-button-style.xml`. 44dp minimum height is a touch target for
  a gloved hand on a vehicle mount, not a cosmetic choice.
- **A ListView cannot live inside a ScrollView.** If a panel's controls are
  taller than the pane, put them in the list's `addHeaderView()` so the whole
  panel is one scroller — and offset click positions by `getHeaderViewsCount()`.
- **`setItemsCanFocus(true)` kills row clicks.** A row containing a Button stops
  firing `OnItemClickListener`; set the click listener on the row view instead.
- **Label sections, and put counts on filters.** Small caps headings (10sp,
  `textAllCaps`, alpha 0.6) over each group. A filter states what it will cost
  before it is used — `Video (1,013)`, not `Video` — otherwise the only way to
  learn what a control does is to toggle it and watch a total move.
- **Toggles are text, not a colored face**: ON in green, OFF in red, on a plain
  dark button.
- **Say what is not being shown.** If a view is truncated or gated, say so in
  words the operator can act on — "map shows nearest 300, zoom in" — because a
  silently trimmed list reads as the whole picture.
- **Write for field operators, not data engineers.** A picker lists the things
  being picked; source names, record counts and provenance belong in the guide,
  not on the control.
- **Distances follow ATAK, never a hardcoded unit.** Read `rab_rng_units_pref`
  and format through `SpanUtilities.formatType(type, metres, Span.METER)`. Note
  `Span.ENGLISH = 0` and `METRIC = 1` — assuming the obvious ordering gets it
  exactly backwards. For a fixed list of values pin the large unit, or 800 m
  shows as "2624 ft" beside entries in miles.
- **A full-width side pane** is `onStateRequested` + `resize()` — subtract
  `HANDLE_THICKNESS` or the grab handle goes off screen and the pane cannot be
  swiped closed.
- **Sharing is `SendDialog.Builder`** (Export → Send → pick an app), which gets
  you Drive, Gmail and the rest for free. Never build your own share sheet.

## Read ATAK's own assets before guessing

`assets/actions` and `assets/menus` inside `atak.apk` define the radial menus and
actions ATAK itself uses. Copying the real definition is faster and more correct
than inferring one — several video-plugin bugs came from guessing what ATAK
expected here.

Other measured facts worth knowing before you spend a day on them:

- **`onMapMoved` runs on the GL thread.** Never touch Views or map items in it:
  it is a native `SIGSEGV` with no Java stack trace. Post to the main thread and
  coalesce.
- **Marker labels render late.** The default is about 10 m/px; widen it with
  `setMaxLabelRenderResolution`. Do not pass your own zoom threshold into it —
  it can be `Float.MAX_VALUE`.
- **Plugin `DrawingShapes` whose points carry altitude vanish under terrain** on
  zoom unless you `setAltitudeMode(ClampToGround)`.
- **`VideoManager.addConnectionEntry` writes to disk synchronously on the calling
  thread.** Use `addConnectionEntries(list, false)` for more than one.
- **ATAK ships GDAL usable from a plugin** (`org.gdal` bindings in `main.jar`,
  drivers in `libgdal.so`) — convert rasters on the device rather than vendoring
  a library.

## Anything that keeps running after the tap

ATAK runs one tool at a time and **ends the active tool** whenever another tool
starts, a dropdown or pane opens, or Back is pressed.

Work that must outlive a tap — a recording, a live feed, a download, a
self-marker listener — lives in a component that lasts for the plugin's life,
never inside a `Tool`. The tool is only its bar. A GPS recording written inside a
tool ends when the operator switches base maps, and it ends silently.

Before every device test, and again before shipping, stage the interruptions that
apply and write down what happened:

- another tool started; a dropdown or pane opened; Back pressed
- base map switched
- pane closed and reopened
- ATAK backgrounded; screen locked; Doze
- network dropped; server dropped; Data Sync present or absent
- plugin reloaded; ATAK killed

## Screenshots are reviewed by eye

No scrub can read a picture. Before any screenshot is committed or published,
look at it for callsigns, coordinates, names, faces, plates and server addresses.
The self marker never belongs in a shot of a map.
