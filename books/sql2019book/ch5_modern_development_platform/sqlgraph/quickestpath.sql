-- Step 1: What is the quickest way for Jacob to become friends with Alice?
SELECT PersonName, Friends
FROM (	
	SELECT
		Person1.name AS PersonName, 
		STRING_AGG(Person2.name, '->') WITHIN GROUP (GRAPH PATH) AS Friends,
		LAST_VALUE(Person2.name) WITHIN GROUP (GRAPH PATH) AS LastNode
	FROM
		Person AS Person1,
		friendOf FOR PATH AS fo,
		Person FOR PATH  AS Person2
	WHERE MATCH(SHORTEST_PATH(Person1(-(fo)->Person2)+))
	AND Person1.name = 'Jacob'
) AS Q
WHERE Q.LastNode = 'Alice';
GO