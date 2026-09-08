# Benchmark capability profiles

Profiles in `profiles/` define the exact skills, plugins, MCP servers, and tools
available to one benchmark run. Local capability files contribute directly to
the profile SHA-256 recorded in the result.

## External skills

External skills are declared by HTTPS GitHub repository, full 40-character
commit, skill path, and license path. The runner fetches the pinned commit into
temporary storage before any model calls, verifies the selected skill and
license files, and includes their Git object identities in the resolved profile
hash.

The upstream repository is not installed into persistent CLI configuration.
Only the selected skill path is mounted into the temporary benchmark plugin.
The checkout is deleted when the run exits.

### Arduino code generator

Profile: `external-arduino-code-generator`

- Repository: <https://github.com/wedsamuel1230/arduino-skills>
- Commit: `d6e77bb2461a2126267e0e00b697b28abe0c0ea2`
- Skill: `skills/arduino-code-generator`
- License: MIT, copyright Samuel F. and contributors
- Upstream license: <https://github.com/wedsamuel1230/arduino-skills/blob/d6e77bb2461a2126267e0e00b697b28abe0c0ea2/LICENSE>

The skill contains references, examples, scripts, templates, and workflow
guidance. Model-visible tools remain controlled by the profile; including a
script in a skill does not grant permission to execute it.
