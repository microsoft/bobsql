-- Step 1: Find John's friends
USE socialnetwork
GO
SELECT Person2.name AS FriendName
FROM Person Person1, friendOf, Person Person2
WHERE MATCH(Person1-(friendOf)->Person2)
AND Person1.name = 'John';
GO

-- Step 2: Find the friends of John's friends
SELECT person1.name +' is friends with ' + person2.name, + 'who is friends with '+ person3.name
FROM Person person1, friendOf friend1, Person person2, friendOf friend2, Person person3
WHERE MATCH(person1-(friend1)->person2-(friend2)->person3)
AND person1.name = 'John';
GO