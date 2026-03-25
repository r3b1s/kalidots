<%*
const title = await tp.system.prompt("Title");
const slug = title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
const platform = await tp.system.prompt("Platform (e.g. htb, thm, bugcrowd)") || "";
const boxName = await tp.system.prompt("Box / lab name") || "";
const url = await tp.system.prompt("URL") || "";
await tp.file.rename(slug);
await tp.file.move("ctf/" + slug);
tR += `---
aliases:
  - ${title}
date: ${tp.date.now("YYYY-MM-DD")}
type: "ctf"
status: draft
platform: ${platform ? `"${platform}"` : ""}
box-name: ${boxName ? `"${boxName}"` : ""}
url: ${url ? `"${url}"` : ""}
tags:
  - ctf
---
# ${title}


## Recon


## Enumeration


## Exploitation


## Privilege Escalation


## Flags


## Notes


`;
await tp.file.cursor(1);
-%>
