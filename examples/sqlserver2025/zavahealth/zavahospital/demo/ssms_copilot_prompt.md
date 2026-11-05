# SSMS GitHub Copilot Prompt – Doctor Notes Search

Use this prompt in SSMS GitHub Copilot Chat (with the `zavahospital` database
in context) to demonstrate semantic search over doctor notes. It is written
from a clinician's perspective — no vector jargon required.

## Prompt

> In the zavahospital database, I want to find doctor notes that describe
> something similar to "patient dehydrated with IV fluids and abnormal vitals"
> — even if the notes don't use those exact words. The notes are in
> clinical.DoctorNotes (NoteText column). Show me the top 50 most similar
> notes with the patient and encounter info.
