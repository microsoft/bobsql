-- Step 1: Create the database and graph tables
USE master;
GO
DROP DATABASE IF EXISTS socialnetwork;
GO
CREATE DATABASE socialnetwork;
GO

USE socialnetwork;
GO

DROP TABLE IF EXISTS Person;
DROP TABLE IF EXISTS Restaurant;
DROP TABLE IF EXISTS City;
DROP TABLE IF EXISTS likes;
DROP TABLE IF EXISTS friendOf;
DROP TABLE IF EXISTS livesIn;
DROP TABLE IF EXISTS locatedIn;
GO
CREATE TABLE Person (id INTEGER PRIMARY KEY NOT NULL, name VARCHAR(100) NOT NULL) AS NODE;
CREATE TABLE Restaurant (id INTEGER PRIMARY KEY NOT NULL, name VARCHAR(100) NOT NULL, city VARCHAR(100) NOT NULL) AS NODE;
CREATE TABLE City (id INTEGER PRIMARY KEY NOT NULL, name VARCHAR(100) NOT NULL, stateName VARCHAR(100) NOT NULL) AS NODE;
CREATE TABLE friendOf AS EDGE;
CREATE TABLE livesIn AS EDGE;
CREATE TABLE locatedIn AS EDGE;
CREATE TABLE likes (rating INTEGER) AS EDGE;
GO

-- Step 2: Insert data into the nodes
INSERT INTO Person VALUES (1,'John');
INSERT INTO Person VALUES (2,'Mary');
INSERT INTO Person VALUES (3,'Alice');
INSERT INTO Person VALUES (4,'Jacob');
INSERT INTO Person VALUES (5,'Julie');
INSERT INTO Person VALUES (6, 'Ginger');
INSERT INTO Person VALUES (7, 'Ryan');
GO
INSERT INTO Restaurant VALUES (1,'Taco Dell','Bellevue');
INSERT INTO Restaurant VALUES (2,'Ginger and Spice','Seattle');
INSERT INTO Restaurant VALUES (3,'Noodle Land', 'Redmond');
INSERT INTO RestaUrant VALUES (4,'BBQ Heaven', 'North Richland Hills');
GO
INSERT INTO City VALUES (1,'Bellevue','wa');
INSERT INTO City VALUES (2,'Seattle','wa');
INSERT INTO City VALUES (3,'Redmond','wa');
INSERT INTO City VALUES (4, 'North Richland Hills', 'tx');
GO

-- Step 3: Insert data into the likes edge which defines who are friends
-- John -> Mary
-- Mary -> Alice
-- Alice -> John
-- Jacob -> Mary
-- Julie -> Jacob
-- Alice -> Ginger
-- Ginger -> Ryan
-- John -> Julie
-- What city people live in
-- What city are restaraunts located in
-- What restaurants do people like and how do they rate it
INSERT INTO friendOf VALUES ((SELECT $NODE_ID FROM Person WHERE ID = 1), (SELECT $NODE_ID FROM Person WHERE ID = 2));
INSERT INTO friendOf VALUES ((SELECT $NODE_ID FROM Person WHERE ID = 2), (SELECT $NODE_ID FROM Person WHERE ID = 3));
INSERT INTO friendOf VALUES ((SELECT $NODE_ID FROM Person WHERE ID = 3), (SELECT $NODE_ID FROM Person WHERE ID = 1));
INSERT INTO friendOf VALUES ((SELECT $NODE_ID FROM Person WHERE ID = 4), (SELECT $NODE_ID FROM Person WHERE ID = 2));
INSERT INTO friendOf VALUES ((SELECT $NODE_ID FROM Person WHERE ID = 5), (SELECT $NODE_ID FROM Person WHERE ID = 4));
INSERT INTO friendOf VALUES ((SELECT $NODE_ID FROM Person WHERE ID = 3), (SELECT $NODE_ID FROM Person WHERE ID = 6));
INSERT INTO friendOf VALUES ((SELECT $NODE_ID FROM Person WHERE ID = 1), (SELECT $NODE_ID FROM Person WHERE ID = 5));
INSERT INTO friendOf VALUES ((SELECT $NODE_ID FROM Person WHERE ID = 6), (SELECT $NODE_ID FROM Person WHERE ID = 7));
GO

INSERT INTO livesIn VALUES ((SELECT $node_id FROM Person WHERE ID = 1),
      (SELECT $node_id FROM City WHERE ID = 1));
INSERT INTO livesIn VALUES ((SELECT $node_id FROM Person WHERE ID = 2),
      (SELECT $node_id FROM City WHERE ID = 2));
INSERT INTO livesIn VALUES ((SELECT $node_id FROM Person WHERE ID = 3),
      (SELECT $node_id FROM City WHERE ID = 3));
INSERT INTO livesIn VALUES ((SELECT $node_id FROM Person WHERE ID = 4),
      (SELECT $node_id FROM City WHERE ID = 3));
INSERT INTO livesIn VALUES ((SELECT $node_id FROM Person WHERE ID = 5),
      (SELECT $node_id FROM City WHERE ID = 1));
INSERT INTO livesIn VALUES ((SELECT $node_id FROM Person WHERE ID = 6),
      (SELECT $node_id FROM City WHERE ID = 4));
INSERT INTO livesIn VALUES ((SELECT $node_id FROM Person WHERE ID = 7),
      (SELECT $node_id FROM City WHERE ID = 4));
GO

INSERT INTO locatedIn VALUES ((SELECT $node_id FROM Restaurant WHERE ID = 1),
      (SELECT $node_id FROM City WHERE ID =1));
INSERT INTO locatedIn VALUES ((SELECT $node_id FROM Restaurant WHERE ID = 2),
      (SELECT $node_id FROM City WHERE ID =2));
INSERT INTO locatedIn VALUES ((SELECT $node_id FROM Restaurant WHERE ID = 3),
      (SELECT $node_id FROM City WHERE ID =3));
INSERT INTO locatedIn VALUES ((SELECT $node_id FROM Restaurant WHERE ID = 4),
      (SELECT $node_id FROM City WHERE ID =4));
GO

INSERT INTO likes VALUES ((SELECT $node_id FROM Person WHERE ID = 1), 
       (SELECT $node_id FROM Restaurant WHERE ID = 1),9);
INSERT INTO likes VALUES ((SELECT $node_id FROM Person WHERE ID = 2), 
      (SELECT $node_id FROM Restaurant WHERE ID = 2),9);
INSERT INTO likes VALUES ((SELECT $node_id FROM Person WHERE ID = 3), 
      (SELECT $node_id FROM Restaurant WHERE ID = 3),9);
INSERT INTO likes VALUES ((SELECT $node_id FROM Person WHERE ID = 4), 
      (SELECT $node_id FROM Restaurant WHERE ID = 3),6);
INSERT INTO likes VALUES ((SELECT $node_id FROM Person WHERE ID = 5), 
      (SELECT $node_id FROM Restaurant WHERE ID = 3),9);
INSERT INTO likes VALUES ((SELECT $node_id FROM Person WHERE ID = 6), 
      (SELECT $node_id FROM Restaurant WHERE ID = 4),10);
INSERT INTO likes VALUES ((SELECT $node_id FROM Person WHERE ID = 7), 
      (SELECT $node_id FROM Restaurant WHERE ID = 4),10);
GO

-- Step 4: Find out who my friends are
-- John wants to find friends in his network. How does he find his *immediate* friends?
USE socialnetwork
GO
SELECT Person2.name AS FriendName
FROM Person Person1, friendOf, Person Person2
WHERE MATCH(Person1-(friendOf)->Person2)
AND Person1.name = 'John';
GO

--Step 5: Who are the friends of my friends?
--John wants to know who are immediate friends of Mary and Julie. Notice this uses a 2nd level traversal of the graph of friends. John now knows he could possible add to his network of friends with Alice and Jacob using Mary and Julie as references.
SELECT person1.name +' is friends with ' + person2.name, + 'who is friends with '+ person3.name
FROM Person person1, friendOf friend1, Person person2, friendOf friend2, Person person3
WHERE MATCH(person1-(friend1)->person2-(friend2)->person3)
AND person1.name = 'John';
GO

--Step 6: Find the restaraunts my friends like
--John is looking for a new restaurant and wants to know which restaurants his friends like
SELECT person2.name, Restaurant.name, likes.rating
FROM Person person1, Person person2, likes, friendOf, Restaurant
WHERE MATCH(person1-(friendOf)->person2-(likes)->Restaurant)
AND person1.name='John';
GO

--Step 7: Who likes restaurants where they live
--John wants to see who likes restaurants in the cities they live in to find out what other choices are out there
SELECT Person.name, Restaurant.name, likes.rating, City.name
FROM Person, likes, Restaurant, livesIn, City, locatedIn
WHERE MATCH (Person-(likes)->Restaurant-(locatedIn)->City AND Person-(livesIn)->City);
GO

--Step 8: Find out my possible social network
--John wants to know what other possible friends are out there to expand his social network. He wants to dive deeper into levels of the graph for the network without having to go one level at a time. The SHORTEST_PATH() keyword can help. This step requires SQL Server 2019.
--John now see that Alice is friends with him but he has not listed Alice as friend. He also notices Ginger (and implictly Ryan) are friends with Alice. He noticed Ginger and Ryan are from Texas and he has a business trip soon there. He could possible talk to Alice about what Ginger and Ryan are like and whether he should try to become friends with them too (and potentially try their favorite BBQ place).
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

--Step 9: Find the quickest way to become friends
--Jacob wants to become friends with Alice through her friends. But he doesn't want to traverse the network of friends manually one level at a time. He can use SHORTEST_PATH() to find the quickest way to become friends with Alice.
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