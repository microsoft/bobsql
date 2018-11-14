-- Create a graph demo database
DROP DATABASE IF EXISTS graphdemo
GO
CREATE DATABASE graphdemo;
GO

USE  graphdemo;
GO

-- Create NODE tables
CREATE TABLE Person (
  ID INTEGER PRIMARY KEY, 
  name VARCHAR(100)
) AS NODE;

CREATE TABLE Restaurant (
  ID INTEGER NOT NULL, 
  name VARCHAR(100), 
  city VARCHAR(100)
) AS NODE;

CREATE TABLE City (
  ID INTEGER PRIMARY KEY, 
  name VARCHAR(100), 
  stateName VARCHAR(100)
) AS NODE;

-- Create EDGE tables. 
CREATE TABLE likes (rating INTEGER) AS EDGE;
CREATE TABLE friendOf AS EDGE;
CREATE TABLE livesIn AS EDGE;
CREATE TABLE locatedIn AS EDGE;
GO