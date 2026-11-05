USE master;
GO
DROP DATABASE IF EXISTS hr;
GO
CREATE DATABASE hr;
GO
USE hr;
GO
-- Create an employees table with checks for valid email addresses and phone numbers
-- With check that cannot be done with LIKE
DROP TABLE IF EXISTS EMPLOYEES;
GO
CREATE TABLE EMPLOYEES (  
    ID INT IDENTITY PRIMARY KEY CLUSTERED,  
    [Name] VARCHAR(150),
    Email VARCHAR(320)
    CHECK (REGEXP_LIKE(Email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')),  
    PhoneNumber NVARCHAR(20)  
    CHECK (REGEXP_LIKE(PhoneNumber, '^(?:\+\d{1,3}[ -]?)?(?:\([2-9]\d{2}\)[ -]?\d{3}-\d{4}|[2-9]\d{2}[ -]?\d{3}-\d{4})$') )
);  
GO

/* Let's breakdown the Regular Expressions

CHECK (REGEXP_LIKE(Email, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'))

^ → Start of the string.

[A-Za-z0-9._%+-]+ → One or more characters that can be:

Uppercase letters A-Z
Lowercase letters a-z
Digits 0-9
Special characters: . _ % + -
(This represents the local part of the email before the @.)

@ → Literal @ symbol separating local part and domain.
[A-Za-z0-9.-]+ → One or more characters for the domain name:

Letters, digits, dot (.), or hyphen (-).

\. → A literal dot before the top-level domain.
[A-Za-z]{2,} → At least two alphabetic characters for the TLD (e.g., com, org).
$ → End of the string.

Emails that work

john.doe@example.com
jane_doe123@sub.domain.org
user+tag@company.co
first.last@my-domain.net
alpha.beta@domain.travel

Ones that fail

john..doe@example.com
jane@domain
user@domain.c
@example.com
john.doe@.com
john@domain..com
john@domain.corporate123

CHECK (REGEXP_LIKE(PhoneNumber, '^(?:\+\d{1,3}[ -]?)?(?:\([2-9]\d{2}\)[ -]?\d{3}-\d{4}|[2-9]\d{2}[ -]?\d{3}-\d{4})$') )

^ → Start of the string.
(?:\+\d{1,3}[ -]?)? → Optional country code:

\+ → Literal plus sign.
\d{1,3} → 1 to 3 digits for country code.
[ -]? → Optional space or hyphen after country code.

(?: ... | ... ) → Alternation for two possible formats:

\([2-9]\d{2}\)[ -]?\d{3}-\d{4} → Format with area code in parentheses:

\([2-9]\d{2}\) → Area code: 3 digits, first digit 2–9.
[ -]? → Optional space or hyphen.
\d{3}-\d{4} → Local number: 3 digits, hyphen, 4 digits.

[2-9]\d{2}[ -]?\d{3}-\d{4} → Format without parentheses:

Starts with 3-digit area code (first digit 2–9).
Optional space or hyphen.
Then 3 digits, hyphen, 4 digits.

$ → End of the string.

Phone numbers that work

+1 (234) 567-8901
(Country code + area code in parentheses + local number)
(234) 567-8901
(Standard U.S. format with parentheses)
234-567-8901
(Standard U.S. format without parentheses)
+91 (987) 654-3210
(International format with country code and parentheses)
234 567-8901
(Space instead of hyphen after area code is allowed)

Phone numbers that don't work

123-456-7890
(Area code starts with 1; regex requires first digit 2–9)
+1234 567-8901
(Country code too long; regex allows only 1–3 digits)
(123)456-7890
(Area code starts with 1; invalid per North American rules)
2345678901
(Missing separators; regex expects hyphen or space)
+1-234-5678-901
(Extra digit in last block; should be 4 digits)
+91-98765-43210
(Does not match U.S. pattern; regex is designed for North American format only) */
