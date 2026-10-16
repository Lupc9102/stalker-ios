# Launcher and touch design

Keep the GTA iOS port's actual UIKit visual hierarchy: dark left-biased artwork,
glass panels, warm primary action, horizontal mode cards, and quiet secondary
actions. Replace title, image and game-specific controls. Do not include GTA art,
community links, cheats, networking or game-specific data readers.

The Zone background was generated using the built-in image generator for this
project, then copied into Resources/ZoneBackdrop.jpg. Prompt:

> Original atmospheric landscape matte painting of the Chernobyl exclusion zone
> at blue-gray dusk; hooded explorer on the far right, abandoned apartment blocks,
> distant ferris wheel, birch trees and wet concrete. Quiet, dark left half for
> readable white launcher text; slate, olive and charcoal, amber horizon; no text,
> logos or interface.

Controls use icons plus labels by default. Extra STALKER actions sit behind
Tools. The editor exposes all actions and includes a collapsible panel to avoid
covering the controls being moved. Three local profiles are independent. Imports
are size/version/range checked; pause cannot be hidden or rebound.

The app has a clearly labelled controls-practice mode. It is not a mock game
scene and must not be described as a functioning STALKER port. Actual UIKit
rendering and device ergonomics have not been verified in this workspace yet.
