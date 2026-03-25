<%*
const title = await tp.system.prompt("Title");
const slug = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
await tp.file.rename(slug);
await tp.file.move("notes/" + slug);
tR += `---
aliases:
  - ${title}
date: ${tp.date.now("YYYY-MM-DD")}
type: "null"
status: draft
tags:
---
# ${title}
`;
await tp.file.cursor(1);
-%>
