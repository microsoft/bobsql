USE graphdemo
GO
INSERT INTO Person VALUES (1,'John');
GO
INSERT INTO Restaurant VALUES (1, 'WeServeBigSteaks', 'Fort Worth')
GO
INSERT INTO likes VALUES ((SELECT $node_id FROM Person WHERE id = 1), 
       (SELECT $node_id FROM Restaurant WHERE id = 1),9);
GO