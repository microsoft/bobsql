# Application layout

Shared layout/navigation components, the assistant dock, and the reconnection
modal for the [Blazor UI](../readme.md).

[MainLayout.razor](MainLayout.razor) and [NavMenu.razor](NavMenu.razor) establish
the frame; [AssistantDock.razor](AssistantDock.razor) hosts the AI surface;
[ReconnectModal.razor](ReconnectModal.razor) supports reconnect feedback.
Companion CSS files own their scoped styling.

Preserve feature-flag visibility, current-page context, and approval interactions.
Verify ordinary navigation as well as assistant-disabled and connection-loss
states before treating a layout change as complete.
