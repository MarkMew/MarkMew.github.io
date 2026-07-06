---
layout: post
title: "How to Reset a Jenkins Build Number: Clear Build History and Set the Next Build Number"
description: "Learn how to clear a Jenkins job's build history and reset its next build number through the Script Console, including the risks and limitations to review first."
author: Mark_Mew
category: [CICD, Jenkins]
tags: [CICD, Jenkins]
date: 2025-8-26
lang: en
---

Some Jenkins Pipelines include the build number in the application version string, for example:

```text
0.0.${BUILD_NUMBER}
```

The final segment comes directly from Jenkins' `BUILD_NUMBER`. After increasing the major or minor version, a team may want the patch number to start from 1 again, which creates a reason to reset the Jenkins build number.

However, a Jenkins build number is designed to be a monotonically increasing identifier. Resetting it is not a routine release operation. To lower the next build number back to 1, the existing build records for that job must first be deleted. This is a destructive administrative operation and should not be treated as a cosmetic cleanup.

## Before You Begin

This article uses the Jenkins Script Console to run a Groovy script. The Script Console has full access to the Jenkins controller and is available only to administrators with the `Overall/Administer` permission.

Before running the script, confirm that:

- The job has no builds currently running or waiting in the queue.
- Any required console logs, artifacts, test reports, and audit records have been backed up.
- No external system still depends on an existing Jenkins build URL or build number.
- You have confirmed the job's full name, especially for jobs inside a Folder or Multibranch Pipeline.
- The script has preferably been tested in a non-production environment and the Jenkins configuration has been backed up.

After the build history is deleted, the previous build pages, records, and artifacts stored under the build directories may not be recoverable. If the goal is only to remove old records, configure a Build Discarder instead of resetting the number.

## Reset the Number from the Script Console

Sign in to Jenkins with an administrator account and open:

```text
Manage Jenkins → Script Console
```

The following is the Groovy script I actually ran. Replace `your-job-name-here` with the name of the target Pipeline before executing it:

```groovy
item = Jenkins.instance.getItemByFullName("your-job-name-here")
// THIS WILL REMOVE ALL BUILD HISTORY
item.builds.each() { build ->
  build.delete()
}
item.updateNextBuildNumber(1)
```

The script retrieves the specified Pipeline, deletes every build-history entry, and sets the next build number to 1. It does not validate the job name or ask for confirmation before deletion, so verify the target and backup status yourself before running it.

## Verify the Result

After the script finishes, return to the job page and confirm that the previous build history has been cleared. When the Pipeline is triggered again, the new build number should start at `#1`. If the Pipeline uses `${BUILD_NUMBER}` in a version string, also make sure that the resulting version does not conflict with an existing artifact, container image, or published package.

## Do You Really Need to Reset It?

If external systems use the build number as a unique identifier, reusing `#1` can make tracking and auditing ambiguous. A more stable design is to let the Jenkins build number continue increasing while keeping the application version and build identifier separate:

```text
Application version: 2.0.0
Build metadata:      Jenkins #183
```

Reset the number only when the build history can be deleted safely and no external system depends on the previous numbers. If you only need to increase the next number, consider the Next Build Number Plugin. Jenkins does not allow the next number to be lowered while larger historical build numbers remain.

---

## References

- [Jenkins Script Console](https://www.jenkins.io/doc/book/managing/script-console/)
- [Jenkins Job API: updateNextBuildNumber](https://javadoc.jenkins.io/hudson/model/Job.html)
- [How to reset build number in Jenkins?](https://stackoverflow.com/questions/20901791/how-to-reset-build-number-in-jenkins)
