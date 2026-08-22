# Key Mapping {#mapping}

## Basic Use {#mapping-basic}

Key Mapping converts a key or key combination into another key or combination.

### How to Use

1. Select “Add Mapping” on the left.
2. Record the source and target combinations in order. Each can contain up to three keys.
3. Verify the displayed combinations, select “Save”, and then select the mapping's checkbox to enable it.

> Set the target to “None” and enable the mapping to block the source key. Clearing the checkbox immediately restores the source key's normal input.

## Combination Rules {#mapping-combo}

- Source and target combinations can contain one to three keys.
- Esc can be used as a normal source or target key.
- A mapping triggers as soon as the last source key is pressed and releases when any source key is released.
- One-, two-, and three-key sources cannot have prefix conflicts. For example, Ctrl and Ctrl+C cannot both be saved.
- Target combinations are not checked for duplicates or prefixes, so multiple mappings can use the same target.
- A wheel direction can only be the last key in a combination.

## Mouse Button Restrictions {#mapping-mouse}

- The left and right mouse buttons cannot be mapped alone or used as the first key in a combination.
- After pressing another key, either mouse button can be recorded as the second or third key.
- Other mappings are suspended while recording. The left and right mouse buttons continue to click normally outside the active recording field.
- Recording is allowed only while Key Mouse Mapper is the foreground window. Switching windows, minimizing, or hiding the app cancels recording immediately.

# Settings {#settings}

## Startup, Tray, and Language {#settings-general}

- Start with Windows runs the app automatically after you sign in.
- Closing the window hides the app while selected mappings remain active.
- Left-click the notification-area icon to show the window again; use its right-click menu to exit completely.
- If you hide the tray icon, start the app again to restore the existing window.
- Changing the language immediately updates the window title, interface, messages, and tray menu without stopping mappings.

## Master Mapping Switch {#settings-input}

- Turning off the title-bar mapping switch immediately releases held outputs and disables every mapping.
- While it is off, all keyboard and mouse buttons return to their original functions. Turning it on re-enables selected mappings.
- The switch is temporary and starts enabled each time the app runs.

## Always on Top {#settings-topmost}

- Use the pin button to keep the window above normal windows. Select it again to turn this off.
