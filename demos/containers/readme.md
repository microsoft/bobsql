# SQL Server Containers demos

In these folders are scripts and instructions to demonstrate SQL Server Containers. They are intended to compliment the presentation Inside SQL Server Containers which can be found on http://aka.ms/bobwardms

The following folders are available for use for demos:

## customize

This is an example of how to build your own image based on the SQL Server image. In this scenario, the image can be used to run a container that enables trace flags.

## docker

These are fundamental demos on docker containers independent of SQL Server

## sqlcontainer

These are demo scripts to show how to run two SQL Server containers and inspect how containers work. In addition, these demos show you how to copy a backup into the container, restore it, and then query it. These demo scripts must be done first in order to run demos for the **sqlcontainerupdate** demos.

## sqlcontainerupdate

These demos show volume store behind the scenes and how to update and upgrade SQL Server containers. You must run the steps in the sqlcontainer demos before using these.
