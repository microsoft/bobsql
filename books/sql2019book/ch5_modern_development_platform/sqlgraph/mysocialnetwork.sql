-- Step 1: What is John's possible social network of friends?
USE socialnetwork;
GO
SELECT
	Person1.name AS PersonName, 
	STRING_AGG(Person2.name, '->') WITHIN GROUP (GRAPH PATH) AS Friends
FROM
	Person AS Person1,
	friendOf FOR PATH AS fo,
	Person FOR PATH  AS Person2
WHERE MATCH(SHORTEST_PATH(Person1(-(fo)->Person2)+))
AND Person1.name = 'John';
GO