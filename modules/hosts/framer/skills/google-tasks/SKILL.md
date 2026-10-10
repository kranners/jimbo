---
name: google-tasks
description: Read, add, complete, rename and delete Aaron's Google Tasks, which stand in for his reminders and to-do lists, through Home Assistant's to-do entities.
---

# Google Tasks

Aaron's reminders and to-do lists are Google Tasks, one Home Assistant `todo.*` entity per task list.
Run `home-assistant-api <METHOD> <path> [json body]` with Bash; it carries the token itself, so never look for or print the token.

## Find the lists

```sh
home-assistant-api GET states \
  | jq '[.[] | select(.entity_id | startswith("todo.")) | {entity_id, name: .attributes.friendly_name, open: .state}]'
```

`state` is the number of unfinished items.
When Aaron names no list, use the one called `My Tasks`, Google's default.

## Read

```sh
home-assistant-api POST 'services/todo/get_items?return_response' '{"entity_id": "todo.my_tasks", "status": "needs_action"}'
```

The reply is `{"service_response": {"todo.my_tasks": {"items": [{"summary", "uid", "status", "due", "description"}]}}}`.
Leave out `status` to include completed items.

## Add

```sh
home-assistant-api POST services/todo/add_item '{"entity_id": "todo.my_tasks", "item": "Buy milk", "due_date": "2026-10-11", "description": "Two litres"}'
```

`due_date` and `description` are optional.
Google Tasks keeps a due date but no time, so a reminder "at 5pm" is saved for that day and the time is said back as lost.

## Complete, rename or reschedule

```sh
home-assistant-api POST services/todo/update_item '{"entity_id": "todo.my_tasks", "item": "Buy milk", "status": "completed"}'
home-assistant-api POST services/todo/update_item '{"entity_id": "todo.my_tasks", "item": "Buy milk", "rename": "Buy oat milk", "due_date": "2026-10-12"}'
```

`item` matches an item's summary or its `uid`; read the list first when the name Aaron says is not exact.

## Delete

```sh
home-assistant-api POST services/todo/remove_item '{"entity_id": "todo.my_tasks", "item": "Buy milk"}'
```

Confirm before deleting, since Google Tasks has no undo from here.

## Speaking the answer

Say at most five items, soonest due first, then how many more there are.
Home Assistant polls Google every 30 minutes, so something added on the phone a moment ago may not be here yet, while anything written here reaches Google at once.
