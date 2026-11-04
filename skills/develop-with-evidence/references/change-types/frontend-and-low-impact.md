# Frontend and low-impact changes

For an interaction change, check at least the user action, the state change, and the visible result; a screenshot proves only the screen it shows. Check loading, empty states, failures, repeated clicks, focus, and the like as this change affects them; a full browser or device matrix is not required by default.

Pure wording, comments, and formatting usually need no new tests and no unrelated builds. When they contain commands, code snippets, config key names, or template expressions, check what those actually do when they run or render.
