# dbman

## import existing database

connect with superuser to db.

add a comment to role

```shell
COMMENT ON ROLE hass IS '{"heritage":"dbman","resource":"hass","namespace":"home-automation"}';
```

add a comment to database

```shell
COMMENT ON DATABASE hass IS '{"heritage":"dbman","resource":"hass","namespace":"home-automation"}';
```

check for existing comments

```shell
\l+
\du+
```

remove comment

```shell
COMMENT ON DATABASE hass IS NULL;
```
