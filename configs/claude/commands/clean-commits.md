---
description: Restructure commit history for cleaner PR review
allowed-tools: Bash(git:*)
---

# Task: Clean Up Git Commit History

## Description
Restructure the commit history of the current branch to make it more readable and reviewer-friendly, while preserving the exact final state of the code. Think of it as "rewriting history" to tell a clearer story of how the changes evolved, without actually changing what the final changes are.

The current branch has changes that work (they pass CI), but the commit history may be messy - with debug commits, WIP commits, reverts, or just poorly organized changes. Transform this into a polished, logical sequence of commits that a reviewer can easily follow and understand.

## Current State

- Branch: !`git branch --show-current`
- Commits ahead of master: !`git rev-list --count master..HEAD`
- Current diff summary: !`git diff --stat master...HEAD`

## Objectives

1. **Analyze** the current changes and understand their purpose
2. **Replace** the existing commits with fresh, well-structured commits
3. **Optimize** each commit to be easy to read, understand, and follow
4. **Create** a clean, clear commit history that makes the changes abundantly clear for reviewers

## Guidelines

### Commit Size: Smaller is Better
- **Err on the side of more, smaller commits** rather than fewer large ones
- Each commit should do ONE thing - if you can split it, split it
- A commit that touches 5 lines is often better than one that touches 50
- When in doubt, make it a separate commit

### Separation of Concerns
- Separate mechanical changes from behavioral changes
- Refactoring commits should contain ONLY refactoring (no new behavior)
- New feature commits should build on clean refactored code
- Keep "move code" separate from "change code"

### Sequential Storytelling (99 Bottles of OOP style)
- Structure commits as a clear narrative a reviewer can follow step-by-step
- Use intermediate "stepping stone" commits that make the journey obvious
- Each commit should be a small, reversible, understandable transformation
- The reviewer should be able to verify each step independently

### Commit Messages
- Use clear, descriptive messages that explain the "what" and "why"
- For refactoring: describe the transformation (e.g., "Extract helper method for X")
- For features: describe the capability added

### The Goal
Maximum reviewer clarity - a reviewer should be able to understand and verify each commit in isolation, following a logical progression from start to finish.

## Critical Requirement

**IMPORTANT**: The final diff must have **NO differences** compared to the current diff, because the current diff passes CI. The end state of the code must be identical - only the commit structure should change.

Before starting, save the current HEAD sha so we can verify the final diff matches.
