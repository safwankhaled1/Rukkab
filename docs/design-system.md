# Rukkab visual system

The canonical logo is assets/brand/rukkab-symbol.svg. Its route forms an R, with pickup/dropoff markers; the mobile CustomPainter uses the same path. Regenerate launcher assets with scripts/render-brand.mjs. Keep Android and iOS icon assets aligned; asset creation does not verify an iOS build.

Use Cairo from the embedded font files and preserve the bundled OFL license. Do not require an external font request for core screens. Main colors are forest ink #203b30, warm orange #ad440c, olive #4c7441 and a warm light surface.

Motion is limited to entry feedback and short button/card transitions. Mobile MotionEntrance runs once without remounting its child and bypasses animation when disableAnimations is true. The admin CSS respects prefers-reduced-motion. Forms must preserve user-entered values during live refreshes.

Filters accumulate until Apply filters is pressed. Filtering, counting and pagination happen together on the server. Name the date dimension explicitly; document expiry is a calendar date, while trip departure and record creation are instants displayed in Asia/Hebron. Label CSV as the displayed page rather than all records.

Guidance consulted: [Material motion](https://m3.material.io/styles/motion/overview), [applying filters](https://www.nngroup.com/articles/applying-filters/), and [known date inputs](https://design-system.service.gov.uk/components/date-input/). These guided purposeful motion, explicit filter application and clear date entry; this project does not claim full Material 3 Expressive compliance.

Verified previews live in work/screenshots. Mobile preview PNGs render the actual production widgets in Flutter tests and are not emulator screenshots. Admin preview data is clearly marked as synthetic.
