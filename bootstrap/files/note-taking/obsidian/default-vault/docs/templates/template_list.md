<%*
const title = await tp.system.prompt("List title");
const slug = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
await tp.file.rename(slug);
await tp.file.move("lists/" + slug);
tR += `---
aliases:
  - ${title}
date: ${tp.date.now("YYYY-MM-DD")}
type: list
status: draft
tags:
---
# ${title}

- 
`;
-%>
