--
-- PostgreSQL database cluster dump
--

\restrict 9g6fOHiM8DwEdg30pb4V6tbcfo4NoaLOIoa99VpvZShItrrVE5IWzMftxossokv

SET default_transaction_read_only = off;

SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;

--
-- Roles
--

CREATE ROLE wms_anon;
ALTER ROLE wms_anon WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB NOLOGIN NOREPLICATION NOBYPASSRLS;
CREATE ROLE wms_api;
ALTER ROLE wms_api WITH NOSUPERUSER INHERIT NOCREATEROLE NOCREATEDB LOGIN NOREPLICATION NOBYPASSRLS;

--
-- User Configurations
--


--
-- Role memberships
--

GRANT wms_anon TO wms_api WITH INHERIT TRUE GRANTED BY hbwms;




\unrestrict 9g6fOHiM8DwEdg30pb4V6tbcfo4NoaLOIoa99VpvZShItrrVE5IWzMftxossokv

--
-- PostgreSQL database cluster dump complete
--

