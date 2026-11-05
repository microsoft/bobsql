USE contactsdb;
GO

-- Create a JSON index
DROP INDEX IF EXISTS [ji_contacts] ON contacts;
GO
CREATE JSON INDEX ji_contacts ON contacts(jdoc) FOR ('$')
WITH (OPTIMIZE_FOR_ARRAY_SEARCH = ON);
GO	

