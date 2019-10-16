-- Step 1: Which restaraunts do John's friends like?
SELECT person2.name, Restaurant.name, likes.rating
FROM Person person1, Person person2, likes, friendOf, Restaurant
WHERE MATCH(person1-(friendOf)->person2-(likes)->Restaurant)
AND person1.name='John';
GO

-- Step 2: How do people rate restaraunts where they live?
SELECT Person.name, Restaurant.name, likes.rating, City.name
FROM Person, likes, Restaurant, livesIn, City, locatedIn
WHERE MATCH (Person-(likes)->Restaurant-(locatedIn)->City AND Person-(livesIn)->City);
GO