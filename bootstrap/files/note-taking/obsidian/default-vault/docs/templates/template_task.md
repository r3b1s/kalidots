<%*
const title = await tp.system.prompt("Task title");
const slug = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
await tp.file.rename(slug);
await tp.file.move("tasks/" + slug);
tR += `---
aliases:
  - ${title}
date: ${tp.date.now("YYYY-MM-DD")}
type: task
status: pending
due:
tags:
---
# ${title}
`;
await tp.file.cursor(1);
-%>
