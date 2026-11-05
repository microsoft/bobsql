# Blazor components

Root components for the [web application](../readme.md):
[App.razor](App.razor), [Routes.razor](Routes.razor),
[ChartCard.razor](ChartCard.razor), and shared imports.

[Pages](Pages/readme.md) contains routable views;
[Layout](Layout/readme.md) contains navigation, layout, assistant, and
reconnection UI. Keep database access in the existing data services rather than
embedding SQL or credentials in components.

Run the application through the first-app instructions and verify both enabled
and disabled feature-flag states when modifying visible behavior.
