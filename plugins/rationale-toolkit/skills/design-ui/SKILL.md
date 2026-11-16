---
name: design-ui
description: "Designs or changes a user-facing screen or flow starting from the user story: who uses it, in what situation, what they need to decide and do. Use when building, changing, or reviewing UI — a page, form, dialog, chat view, settings screen, dashboard, or native app screen. Triggers on: 'add a page/screen for', 'redesign this view', 'this UI is confusing', any feature whose result the user sees on screen. Not for animation craft or choosing a component library."
---

# Design UI from the User Story

Start from the person using it, not from the data model or the component tree.

1. Write the user story before designing: who, in what situation, doing what, needing which information, how they learn the result. A screen that cannot be tied to a story is not designed yet.
2. Use familiar conventions. A kind of app's expected structure is itself a requirement (chat UI: message bubbles, avatars, an input bar at the bottom). Follow the project's existing visual style, components, and spacing instead of introducing new ones.
3. Show what the user needs to decide and act, and nothing that only the implementation needs: no internal names, file paths, IDs, or implementation terms in user-facing text.
4. Verify by walking the whole story, per `verify-outcomes` (runtime verification). Stay on the devices and platforms the user named; do not widen that scope on your own.
