# manual steps

after init we need to run

```sql
CREATE ROLE windmill_user;

GRANT ALL
ON ALL TABLES IN SCHEMA public
TO windmill_user;

GRANT ALL PRIVILEGES
ON ALL SEQUENCES IN SCHEMA public
TO windmill_user;

ALTER DEFAULT PRIVILEGES
    IN SCHEMA public
    GRANT ALL ON TABLES TO windmill_user;

ALTER DEFAULT PRIVILEGES
    IN SCHEMA public
    GRANT ALL ON SEQUENCES TO windmill_user;


CREATE ROLE windmill_admin WITH BYPASSRLS;
GRANT windmill_user TO windmill_admin;
```

as psql super user connected to windmill database see: <https://github.com/windmill-labs/windmill/issues/5079#issuecomment-2598663050>
