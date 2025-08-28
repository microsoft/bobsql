USE hr;
GO

INSERT INTO EMPLOYEES ([Name], Email, PhoneNumber)
VALUES ('LeBron James', 'lebron.james@basketball.com', '(234) 567-8901');
INSERT INTO EMPLOYEES ([Name], Email, PhoneNumber)
VALUES ('Serena Williams', 'serena.williams@tennis.org', '(345) 678-9012');
INSERT INTO EMPLOYEES ([Name], Email, PhoneNumber)
VALUES ('Lionel Messi', 'lionel.messi@soccer.net', '(456) 789-0123');
INSERT INTO EMPLOYEES ([Name], Email, PhoneNumber)
VALUES ('Tom Brady', 'tom.brady@football.co', '(567) 890-1234');
INSERT INTO EMPLOYEES ([Name], Email, PhoneNumber)
VALUES ('Roger Federer', 'roger.federer@tennis.com', '(678) 901-2345');
INSERT INTO EMPLOYEES ([Name], Email, PhoneNumber)
VALUES ('Simone Biles', 'simone.biles@gymnastics.org', '(789) 012-3456');
INSERT INTO EMPLOYEES ([Name], Email, PhoneNumber)
VALUES ('Cristiano Ronaldo', 'cristiano.ronaldo@soccer.co', '(890) 123-4567');
INSERT INTO EMPLOYEES ([Name], Email, PhoneNumber)
VALUES ('Michael Phelps', 'michael.phelps@swimming.net', '(901) 234-5678');
INSERT INTO EMPLOYEES ([Name], Email, PhoneNumber)
VALUES ('Usain Bolt', 'usain.bolt@track.com', '(212) 345-6789');
GO

-- Find emails that end with .org and whose local-part contains a dot followed by a token that begins with will and continues with letters only for at least 3 more characters.
-- (This distinguishes williams from, say, will9 or will__ and uses a variable-length, letters-only rule that LIKE can’t express cleanly.)
SELECT [Name], Email
FROM dbo.EMPLOYEES
WHERE REGEXP_LIKE(LOWER(Email), '^[^@]*\.will[a-z]{3,}@[a-z0-9.-]+\.org$');
GO