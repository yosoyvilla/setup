/**
 * Unit tests for plugins/harness-guards.js. Run: node scripts/test-harness-guards.mjs
 * Every assertion is falsifiable: each has at least one input asserting the
 * negative case, so a regex matching everything (or nothing) fails the suite.
 */
import assert from "node:assert/strict"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import * as t from "./harness-guards-lib.mjs"

let n = 0
function ok(cond, msg) {
  n++
  assert.ok(cond, msg)
}

// --- SECRET_RE: must match real secret shapes, must NOT match prose ----------
ok(t.SECRET_RE.test("ghp_" + "a1B2c3D4e5F6g7H8i9J0k1L2"), "matches GitHub PAT")
ok(t.SECRET_RE.test("AKIA" + "IOSFODNN7EXAMPLE"), "matches AWS access key id")
ok(t.SECRET_RE.test("-----BEGIN RSA " + "PRIVATE KEY"), "matches PEM header")
ok(t.SECRET_RE.test("xoxb-" + "123456789012-abcdefghijkl"), "matches Slack token")
ok(t.SECRET_RE.test("sk-ant-api03-" + "x".repeat(24)), "matches Anthropic key")
ok(!t.SECRET_RE.test("set the API key in the .env file"), "prose mention of api key not blocked")
ok(!t.SECRET_RE.test("export ANTHROPIC_API_KEY=  # value comes from vault"), "var name alone not blocked")
ok(!t.SECRET_RE.test("eyJhbGciOiJIUzI1NiJ9"), "lone JWT header segment not blocked")

// --- file classifiers ---------------------------------------------------------
ok(t.DOC_FILE_RE.test("README.md"), "md is doc")
ok(t.DOC_FILE_RE.test("notes/AGENTS.md"), "nested md is doc")
ok(!t.DOC_FILE_RE.test("config/settings.py"), "py is not doc")
ok(t.UI_FILE_RE.test("frontend/src/components/AdCard.jsx"), "jsx is UI")
ok(t.UI_FILE_RE.test("src/pages/Dashboard.tsx"), "pages/ tsx is UI")
ok(t.UI_FILE_RE.test("frontend/src/services/api.js"), "file under frontend/ is UI")
ok(!t.UI_FILE_RE.test("backend/apps/core/views.py"), "backend py is not UI")
ok(t.CODE_FILE_RE.test("apps/core/views.py"), "py is code")
ok(!t.CODE_FILE_RE.test("docs/README.md"), "md is not code")
ok(t.MANIFEST_RE.test("backend/requirements.txt"), "requirements.txt is manifest")
ok(t.MANIFEST_RE.test("requirements-dev.txt"), "requirements-dev.txt is manifest")
ok(t.MANIFEST_RE.test("frontend/package.json"), "package.json is manifest")
ok(!t.MANIFEST_RE.test("package-lock.json"), "lockfile alone is not the manifest")

// --- command classifiers -------------------------------------------------------
ok(t.INSTALL_CMD_RE.test("pip install requests"), "pip install detected")
ok(t.INSTALL_CMD_RE.test("docker exec swipe-backend pip3 install requests"), "pip inside docker exec detected")
ok(t.INSTALL_CMD_RE.test("pnpm add axios"), "pnpm add detected")
ok(!t.INSTALL_CMD_RE.test("npm install"), "bare npm install (from lockfile) not an obligation")
ok(!t.INSTALL_CMD_RE.test("pip list"), "pip list not an install")
ok(t.TEST_CMD_RE.test("python -m pytest backend/"), "pytest detected")
ok(t.TEST_CMD_RE.test("npm test"), "npm test detected")
ok(t.TEST_CMD_RE.test("python e2e_test.py"), "e2e_test script detected")
ok(!t.TEST_CMD_RE.test("npm run build"), "build is not a test run")

// --- protected bash -----------------------------------------------------------
ok(t.BASH_PROTECTED_RE.test("echo SECRET=1 >> backend/.env"), "append into .env blocked")
ok(t.BASH_PROTECTED_RE.test("cat creds | tee infra/terraform.tfstate"), "tee into tfstate blocked")
ok(t.BASH_PROTECTED_RE.test("rm -f deploy/key.pem"), "rm of pem blocked")
ok(t.BASH_PROTECTED_RE.test("cp ~/.ssh/id_rsa /tmp/x"), "cp of id_rsa blocked")
ok(!t.BASH_PROTECTED_RE.test("echo DEBUG=True >> backend/.env.example"), ".env.example append allowed")
ok(!t.BASH_PROTECTED_RE.test("cat backend/.env.example"), "reading env example allowed")
ok(!t.BASH_PROTECTED_RE.test("grep -r PIXABAY backend/"), "ordinary grep allowed")

// --- obligation state machine ---------------------------------------------------
t.state.codeEdited.clear(); t.state.uiEdited.clear(); t.state.installs.length = 0
t.state.gitMissing = false; t.state.gitChecked = true

ok(t.obligationBlock() === null, "clean state produces no injection")

t.classifyEdit("frontend/src/components/SubmitForm.jsx")
ok(t.state.uiEdited.size === 1 && t.state.codeEdited.size === 1, "jsx counts as UI and code")
ok(t.obligationBlock().includes("UI VERIFICATION"), "UI obligation present after jsx edit")
ok(t.obligationBlock().includes("TESTS"), "test obligation present after edit")

t.classifyBash("cd frontend && npm test")
ok(!t.obligationBlock()?.includes("TESTS:"), "test run clears test obligation")

t.state.uiEdited.clear() // simulates browser-tool observation (tool.execute.after path)
t.classifyBash("pip install django-environ")
ok(t.obligationBlock().includes("DEPENDENCY MANIFEST"), "install without manifest is an obligation")
t.classifyEdit("backend/requirements.txt")
ok(t.obligationBlock() === null, "manifest edit clears dependency obligation")

// --- git detection ---------------------------------------------------------------
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "hg-test-"))
t.state.gitChecked = false
t.checkGit(tmp)
ok(t.state.gitMissing === true, "bare tmp dir detected as git-less")
ok(t.obligationBlock().includes("VERSION CONTROL"), "git obligation injected")
fs.mkdirSync(path.join(tmp, ".git"))
t.state.gitChecked = false
t.checkGit(tmp)
ok(t.state.gitMissing === false, ".git dir clears git obligation")
fs.rmSync(tmp, { recursive: true, force: true })

console.log(`harness-guards: ${n} assertions passed`)
