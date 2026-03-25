<%*
const title = await tp.system.prompt("Project title");
const slug = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
await tp.file.rename(slug);
await tp.file.move("projects/" + slug);
tR += `---
aliases:
  - ${title}
date: ${tp.date.now("YYYY-MM-DD")}
type: project
status: active
due:
tags:
---
# ${title}
`;
await tp.file.cursor(1);
-%>
