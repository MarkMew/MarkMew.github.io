---
layout: post
title: How to Reset Jenkins Build Numbers
author: Mark_Mew
category: [CICD, Jenkins]
tags: [CICD, Jenkins]
date: 2025-8-26
---

When I used to run pipeline builds,

I often structured version numbers as three segments like `0.0.{buildNumber}`.

The last segment used the Jenkins build number.

But once the minor or major version increases,

that trailing build number can become awkward.

Jenkins provides a way to reset build numbers.

First, log in to Jenkins,

then open the Script Console page in settings.

Paste and run the following code.

Remember to replace `your-job-name-here` with your pipeline job name.

```java
item = Jenkins.instance.getItemByFullName("your-job-name-here")
//THIS WILL REMOVE ALL BUILD HISTORY
item.builds.each() { build ->
  build.delete()
}
item.updateNextBuildNumber(1)
```

After execution, your pipeline will look like a fresh one.

When you bump versions and want to reset the build number,

~~or when a new pipeline has too many errors and you want to hide the mess~~

this is a simple and useful snippet.



---

References

[How to reset build number in jenkins?](https://stackoverflow.com/questions/20901791/how-to-reset-build-number-in-jenkins)
