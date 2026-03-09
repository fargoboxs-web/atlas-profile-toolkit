# README Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rewrite the public README in Chinese so the repository is understandable and useful to Atlas users who frequently switch to fresh accounts.

**Architecture:** Keep the repository structure unchanged and focus the change on documentation. Reframe the README around user pain points, user stories, quick start, recommended workflows, command reference, and clear safety boundaries.

**Tech Stack:** Markdown

---

### Task 1: Rewrite README for public users

**Files:**
- Modify: `/Users/fargobox/Downloads/atlas-profile-toolkit/README.md`

**Step 1: Write the failing test**

Manual expectation:
- README should clearly explain who this project is for, what problem it solves, and how to get started in a few minutes.

**Step 2: Run test to verify it fails**

Run:
`rg -n "适用人群|用户故事|快速上手|常见问题" /Users/fargobox/Downloads/atlas-profile-toolkit/README.md`

Expected:
- missing or incomplete matches before the rewrite

**Step 3: Write minimal implementation**

Rewrite README to include:
- one-sentence project introduction
- target user profile
- user stories
- what the tool solves and what it does not solve
- quick start
- recommended workflows
- command reference
- safety boundaries
- FAQ

**Step 4: Run test to verify it passes**

Run:
`rg -n "适用人群|用户故事|快速上手|常见问题" /Users/fargobox/Downloads/atlas-profile-toolkit/README.md`

Expected:
- all sections present

**Step 5: Commit**

```bash
cd /Users/fargobox/Downloads/atlas-profile-toolkit
git add README.md docs/plans/2026-03-09-readme-refresh.md
git commit -m "docs: rewrite public readme"
```

### Task 2: Verify and publish

**Files:**
- Verify: `/Users/fargobox/Downloads/atlas-profile-toolkit/README.md`

**Step 1: Verify required sections exist**

Run:
`rg -n "适用人群|用户故事|快速上手|常见问题" /Users/fargobox/Downloads/atlas-profile-toolkit/README.md`

Expected:
- all sections found

**Step 2: Check git status**

Run:
`git -C /Users/fargobox/Downloads/atlas-profile-toolkit status --short --branch`

Expected:
- only intended README and plan-doc changes

**Step 3: Commit and push**

Run:
`git -C /Users/fargobox/Downloads/atlas-profile-toolkit push`

Expected:
- README update published to GitHub
