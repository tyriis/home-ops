# home-assistant

Home Assistant is the automation runtime for the home. Motion and light
automations that used to live in Node-RED were rebuilt natively here; the
Node-RED deployment was retired in
[ADR 0025](https://github.com/tyriis/home-ops/blob/main/docs/decisions/0025-deprecate-and-remove-node-red.md).

## Automations

- [office light](flows/office.md)
- [basement light](flows/basement.md)

## Conventions

Both automations take a lock from `locking-service` instead of writing the light
state directly. A motion event either takes the lock or refreshes its duration;
while the lock is held, other state transitions are blocked. Every automation
below therefore works with a fixed set of system states rather than with
individual triggers.
