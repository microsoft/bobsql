# Auditing session-context probe

[Program.cs](Program.cs) is a .NET console companion to the
[auditing walkthrough](../README.md).

It accepts server and database arguments, connects using encrypted Entra
authentication, records a UTC observation window, sets synthetic session-context
values, and verifies them on the SQL session. The parent instructions explain
how to correlate the resulting activity with auditing evidence.

This is a diagnostic probe, not the application authorization boundary.
Use the lab identity and target specified by the parent. Do not substitute
real patient or clinician information into test output.
