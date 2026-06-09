---
name: sync-vault
description: Sync the Obsidian knowledge base with current Claude Code configuration. Use after modifying agents, skills, hooks, rules, plugins, or settings.
user-invocable: true
disable-model-invocation: true
---

Sync the Obsidian vault at ~/Documents/obsidian-vault/ with the current Claude Code configuration.

## Steps

1. Read the current state of all configuration:
   - ~/.claude/settings.json (model, plugins, hooks)
   - ~/.claude/settings.local.json (permissions)
   - ~/.claude/CLAUDE.md (global rules)
   - ~/.claude/agents/*.md (all agents)
   - ~/.claude/skills/*/SKILL.md (all skills)
   - ~/.claude/rules/*.md (shared rules)

2. Read the current vault documentation:
   - ~/Documents/obsidian-vault/claude-code/setup.md
   - ~/Documents/obsidian-vault/claude-code/multi-project-workflow.md
   - ~/Documents/obsidian-vault/claude-code/tips-and-tricks.md

3. Compare and identify differences between the actual config and vault docs.

4. Update the vault files to match the actual current state. Focus on:
   - Agent list, models, maxTurns, descriptions
   - Plugin list
   - Hook list
   - Skill list
   - Security settings (denylists, protected files)
   - Routing rules
   - Any new features or changes

5. Update project files if needed:
   - ~/Documents/obsidian-vault/projects/*.md

6. Commit and push:
   ```bash
   cd ~/Documents/obsidian-vault && git add -A && git commit -m "<descriptive message>" && git push
   ```

7. Report what was updated.
