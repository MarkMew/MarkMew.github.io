---
layout: post
title: "How Should I Start Introducing CI/CD?"
description: "A beginner-friendly guide for teams that have not yet adopted CI/CD, starting from version control, automated deployment workflows, environment variables, and target environment permissions."
author: Mark_Mew
categories: [CICD]
tags: [CICD, DevOps, SRE, Platform Engineering]
keywords: [CICD, CI, CD, DevOps, SRE, Platform Engineering, Automated Deployment]
lang: en
date: 2026-06-16
---

DevOps is probably a term many people are already tired of hearing.

Especially in an age of information overload,

there is no shortage of places to learn new concepts.

Some people say DevOps is a culture.

Some say DevOps is automated deployment.

I can agree with both to some extent.

But what many people really want to ask is:

"Where do I actually start?"

Or, more specifically:

how do I introduce automated deployment?

For some teams, the problem is not that they do not want to improve.

It is that they do not know where the first step should be.

So this article will not focus on abstract terminology,

nor on cultural slogans that may or may not be practical in the short term.

Instead, I will take a more practical approach.

Before talking too much about DevOps,

let's start with CI/CD

and make day-to-day development and deployment more stable and easier to work with.

## Why Start with CI/CD

CI stands for Continuous Integration.

CD stands for Continuous Delivery or Continuous Deployment.

There are many things we can discuss under the DevOps umbrella.

So why should we begin with CI/CD?

Or more specifically, why should we begin with CD, meaning automated deployment?

The reason is simple:

this is one of the easiest areas where teams can see immediate results.

If you are reading this article and have made it this far,

you probably have some expectations for improving your current workflow.

You may also want to grow as an engineer and improve the way your team develops and ships software.

Discussing culture and breaking down the wall between development and operations

usually requires management support and organizational alignment.

Before the basic mechanisms are in place,

it is even harder to talk about centralized logging, alerting, SLOs, or incident management.

At this stage, what you need most is not a fancy term.

You need automation.

More specifically,

you need to automate application deployment first.

When teammates start seeing fewer deployment mistakes,

or even near-zero manual errors,

the team will begin to trust the approach.

Only then does it become easier to discuss other DevOps, SRE, or platform engineering practices.

## How to Introduce Automated Deployment

### Put Code in Version Control

Some people may be surprised to see this as the first step.

We are already in the AI era.

Git has been around for a long time.

Do we still need to remind people to put code in version control?

Unfortunately, yes.

Outside large companies,

some small companies, or teams with only one engineer,

may still not have their code properly managed in a version control system.

AWS Lambda development is a common example.

The AWS Cloud Console provides a convenient environment

where developers can edit code directly inside AWS Lambda.

Python developers can even use packages such as `AWSLambdaPowertoolsPythonV2`,

and in simple cases, they may not even need to write a requirements.txt explicitly

before the function can run.

This convenience makes it very easy to ignore one important fact:

the source code may not be in version control at all.

Even if you use Lambda `Versions`,

what it actually does is create a snapshot of the runtime, environment variables, and Lambda configuration.

That is not the same as source code version control.

When you need to change environment variables,

or configure VPC, Security Groups, IAM Roles, and other settings,

too many configuration changes can make rollback difficult.

You may need to reconfigure settings manually,

or end up with a large number of hard-to-understand Lambda versions.

> Before SVN and Git became common,
> how did people manage systems when code was not in version control?
> Usually, someone would SSH or remote desktop into a server,
> go to the directory where the files lived,
> rename the file they were about to change as a backup,
> and then leave that file on the machine
> until one day nobody remembered whether it was safe to delete.
> ```
> index.php
> index.php_20260616
> index.php_20260616_2
> ```
{: .prompt-info}

So the first step of CI/CD is not writing YAML.

It is not choosing Jenkins, GitLab CI, GitHub Actions, or any other tool either.

The first step is making sure the code is actually in version control,

and that the team can use Git to answer questions such as:

- Which version is currently running in production?
- What changed in this release?
- Who changed what, and when?
- Which version should we roll back to if something goes wrong?

Without version control,

CI/CD is just automating an unstable process.

## Automated Deployment

To implement automated deployment,

I recommend starting with three key areas:

`deployment workflow`, `environment variables`, and `target environment permissions`.

### Deployment Workflow

The deployment workflow must be repeatable.

It should not only work the first time.

It should work the second time, the third time, and every time after that.

Whether you are deploying to SIT, UAT, or production,

the process should be as consistent as possible across environments.

The deployment steps should not change just because the environment changes.

The system should also not collapse simply because one environment is missing initial data.

A good deployment workflow should at least answer these questions:

- Which Git branch or tag does the code come from?
- How are dependencies installed?
- How are tests executed?
- How is the artifact built or packaged?
- How is the artifact deployed to the target environment?
- What happens when deployment fails, and how do we stop or roll back?

You do not need to make it perfect at the beginning.

If your team has never had CI/CD,

the first version can be simple.

For example:

`push code` → `run tests` → `deploy to a test environment`

After this workflow becomes stable,

you can gradually add production deployment, approval gates, version tags, rollback strategies, and notifications.

### Environment Variables

Different environments usually have different database connections.

Even if you want to save cost

and let the `test environment` and `production environment` share the same database host,

you should at least separate database names or schemas.

Therefore, these values should not be hard-coded in the application.

A better approach is to separate configuration from code

and load different settings for different environments through configuration files, environment variables, Secret Manager, Parameter Store,

or another configuration management mechanism.

If database connections, API keys, and third-party service URLs are hard-coded,

manual changes during deployment can easily cause mistakes.

Worse,

sensitive information may be committed into Git,

creating a security issue.

For beginners,

the basic principles are:

- Code describes behavior
- Environment variables describe environment differences
- Secrets should not appear in Git
- Test and production environments must be clearly distinguishable

Once these boundaries are clear,

CI/CD can truly deploy the same codebase to different environments.

### Target Environment Permissions

Permissions for the target environment may be account credentials,

different private keys,

or agents installed in each environment

that actively or passively retrieve deployment content.

Whichever approach you choose,

the key point is that the CI/CD system must have permission to deploy to the target environment.

However, more permission is not better.

When beginners first introduce CI/CD,

it is easy to grant overly broad permissions just to make the pipeline work.

This may feel convenient in the short term,

but it becomes risky over time.

A better approach is to follow the principle of least privilege.

If CI/CD needs to deploy Lambda,

grant only the permissions needed to deploy Lambda.

If CI/CD needs to upload artifacts to S3,

grant only the required permissions for the target bucket.

If CI/CD needs to restart a service,

grant only the permission to operate that service.

Deployment permissions should also be managed and tracked.

Once CI/CD can modify production,

it is no longer just a developer tool.

It becomes part of the production change management process.

## Start with a Minimum Viable Workflow

If you have no idea where to start,

use a minimum viable workflow as your first goal.

Do not try to automate everything from day one.

Do not try to build a full platform engineering experience at the beginning either.

First, make one service deployable to a test environment through CI/CD.

Then make the same workflow deployable to production.

For example:

1. Put code in Git
2. Trigger the pipeline on push or merge request
3. Run basic tests in the pipeline
4. Build the deployment artifact
5. Automatically deploy to the test environment
6. Deploy to production after manual approval
7. Notify the team of the deployment result

This workflow may not look fancy,

but it is already enough to improve many daily problems.

For example:

- No more manual file copying
- No more logging into servers to edit code
- No more relying on memory to know what was deployed
- No more worrying about missing a deployment step every time
- Easier tracking when something breaks

Once this workflow becomes stable,

you will naturally see what needs to be improved next.

Maybe automated tests are insufficient.

Maybe environment variables are messy.

Maybe there is no post-deployment health check.

Maybe there is no alerting or log tracing.

When these problems surface,

that is the right time to move further into DevOps, SRE, or platform engineering.

## Conclusion

Introducing CI/CD does not require you to behave like a mature large-scale engineering organization from day one.

For teams that have not started yet,

the most important thing is to build a reliable, repeatable, and traceable deployment workflow first.

As long as code is version controlled,

deployment can be repeated,

environment differences are managed through configuration,

and target environment permissions are properly controlled,

the team has already taken a major step toward a more mature engineering process.

DevOps does not start from slogans.

It starts when development and operations can trust the same delivery workflow.

SRE does not require a complete reliability engineering system at the beginning.

It starts by making every change more controlled, more observable, and easier to recover from.

Platform engineering does not need to begin with a large internal platform.

It starts by gradually turning repetitive, error-prone team workflows into productized and self-service capabilities.

So if you are wondering where to begin,

do not be intimidated by terms like DevOps, SRE, or platform engineering.

Start with a minimum viable CI/CD pipeline.

Make deployment stable.

Make changes traceable.

Let the team slowly build trust in automation.

Once that foundation is in place,

culture, reliability, and platformization

will have a real place to grow from.
