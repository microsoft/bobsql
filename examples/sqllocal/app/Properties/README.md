# Local launch profiles

[launchSettings.json](launchSettings.json) contains ASP.NET Core development
launch profiles: HTTP on `localhost:5099`, and HTTPS on `localhost:7030`
with HTTP also available. Profiles are local development settings, not
deployment configuration or credentials.

The [app runner](../run.ps1) selects the HTTP profile. The HTTPS profile
requires a trusted ASP.NET development certificate. Keep connection strings
with credentials out of launch settings; use the runtime configuration
override documented in the [app README](../README.md).

Do not change the binding to a public interface without adding appropriate
authentication, authorization, transport security, and network controls.
