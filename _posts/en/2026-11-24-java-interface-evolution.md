---
layout: post
title: "The Evolution of Java Interfaces: From default and private Methods to Sealed Interfaces and Records"
description: "A walkthrough of how Java interfaces evolved from Java 8 to Java 21: how default methods keep published APIs backward compatible, what Java 9 private methods fix, how to resolve conflicting default methods, and how Java 16 records and Java 17 sealed interfaces work with Java 21 switch pattern matching, with a comparison to Python dataclasses."
author: Mark_Mew
categories: [Java]
tags: [Java, Interface, Record, Sealed, Pattern Matching, Python]
keywords: [Java interface, Java default method, Java private interface method, Java 8 default method, Java 9 private method, sealed interface, permits, Java record, record pattern, switch pattern matching, Java 21, dataclass]
lang: en
date: 2026-11-24
---

Are all Java interface methods public, and can they all be inherited and implemented?

The answer is both right and wrong, depending on the Java version you use. Before Java 8, interface methods were implicitly `public abstract` and had to be implemented by implementing classes, so saying they are all public was true. Later versions gradually changed this: Java 8 added `default` and `static` methods, which must be public, and implementing classes can choose to override them; Java 9 added `private` methods, which let default methods share internal logic without exposing helper methods; Java 17 added `sealed` interfaces, which use `permits` to restrict implementation to the listed classes or subinterfaces.

This post goes through these changes version by version, explains the problem each feature solves, and shows an example of each.

## Overview by Version

After Java 9, no new kinds of members were added to interfaces. Later changes are about *how interfaces can be used*, such as sealed types and pattern matching.

| Version | What was added | Access modifiers |
| --- | --- | --- |
| Java 7 and earlier | Abstract methods, constants | Methods are `public abstract`; constants are `public static final` |
| Java 8 | `default` methods, `static` methods | Must be `public` |
| Java 9 | `private` methods, `private static` methods | `private`, and must have a body |
| Java 16 | Records can implement interfaces; local interfaces can be declared | — |
| Java 17 | `sealed` interfaces (`permits`) | — |
| Java 21 | `switch` pattern matching and record patterns, with exhaustiveness checks for sealed types | — |

> Interfaces still don't allow `protected` methods.
{: .prompt-info}

## Java 8: default Methods

Default methods exist mainly for one reason: **you can add a method to an interface that's already been published, and existing implementations still compile while you ship new functionality.** The JDK itself relied on this to add `forEach()` and `stream()` to `Iterable` and `Collection`.

### Scenario: Adding a Method to a Published Library

Say v1.0 of your library is already widely used. Users have written implementations like `Circle implements Shape` that you can't see or change:

```java
public interface Shape {
    double area();
}
```

**The Java 7 way**: add another abstract method. As soon as users upgrade, every implementation fails to compile.

```java
public interface Shape {
    double area();
    String describe();   // added in v2.0 → breaks every existing implementation
}
```

**The Java 8 way**: provide a default implementation with `default`. Users don't need to change anything, and they can still override it if they want.

```java
public interface Shape {
    double area();

    default String describe() {
        return "Area: " + area();
    }
}
```

### Workarounds Before Java 8

Without default methods, the JDK had to use one of these approaches, each with drawbacks:

| Approach | JDK example | Drawback |
| --- | --- | --- |
| A new sub-interface | `LayoutManager2 extends LayoutManager` | Callers need `instanceof` checks everywhere, and the API is fragmented |
| A static utility class | `Collections` | Methods don't belong to the interface, are hard to discover, and can't be overridden per implementation |
| Interface + skeletal abstract class | `List` + `AbstractList` | One more class, and you're limited by single inheritance |

### Other Benefits

- Implementations don't repeat the same code; they only implement what actually differs.
- More flexible than an abstract class: a class can extend only one parent class, but it can implement any number of interfaces.
- Functional interfaces can provide handy methods on top of the single abstract method a lambda implements, such as `reversed()` and `thenComparing()` on `Comparator`:

```java
Comparator<Person> byAge = (a, b) -> a.age - b.age;
Comparator<Person> c = byAge.reversed().thenComparing(p -> p.name);
```

### Rule of Thumb

Leave behavior that varies by implementation to abstract methods. Default methods fit functionality that's common to all implementations and can be built from the interface's other methods.

## Java 9: private Methods

Private methods let multiple default methods share internal logic without turning helper methods into public API.

Before Java 8, interfaces had no implementation at all, so there was no need for private methods. The need only appeared once default methods existed.

### The Problem in Java 8

```java
public interface Shape {
    double area();

    default String describe() { return "Area: " + fmt(area()); }
    default String toJson()   { return "{\"area\": " + fmt(area()) + "}"; }

    default String fmt(double d) {     // can only be public in Java 8
        return String.format("%.2f", d);
    }
}
```

`fmt` is just an internal helper, but in Java 8 it has to be public, which causes these problems:

- Outside code can call `shape.fmt(...)` and assume it's meant to be used.
- An implementation might accidentally override `fmt`, changing the output of `describe()` in a way that's hard to track down.
- Changing the signature of `fmt` later breaks anyone who calls it.
- The only way to keep it private is to copy the logic into every default method.

### The Java 9 Way

```java
    private String fmt(double d) {
        return String.format("%.2f", d);
    }
```

With a one-keyword change, outside code can't see it, implementations can't override it, and the author can change it at any time.

### Rules

- Private methods must have a body; they can't be abstract.
- Private instance methods can only be called from default methods or other private instance methods.
- Private static methods can be called from both static and non-static methods.

### How default and private Divide the Work

Default methods solve a compatibility problem *for users*; private methods solve a code organization problem *for library authors*.

Both pain points mainly show up when an interface is already published and implemented by other people. If an interface is only used inside your own project, you won't feel them much.

## Conflicting default Methods

Once interfaces can have implementations, there's a new question: if a class implements two interfaces that both have a default method with the same name and parameters, which one wins?

Java requires the class to override the method itself, and you can use `A.super.method()` to pick a version:

```java
interface A { default String hello() { return "A"; } }
interface B { default String hello() { return "B"; } }

class C implements A, B {
    @Override
    public String hello() {
        return A.super.hello();   // explicitly use A's version
    }
}
```

Interfaces can also use `extends` to inherit from one or more interfaces, for example `interface D extends A, B {}`.

## Java 16: Records

A record is an immutable class designed purely to hold data. A one-line declaration replaces the boilerplate constructor, accessors, `equals`, `hashCode`, and `toString`:

```java
public record Point(int x, int y) {}

Point p = new Point(1, 2);
p.x();                         // 1 (it's x(), not getX())
p.equals(new Point(1, 2));     // true, compared by content
System.out.println(p);         // Point[x=1, y=2]
```

### Characteristics

- Fields are `private final`: immutable, with no setters.
- Implicitly `final`: a record can't be extended and can't extend another class, but it **can implement interfaces**.
- You can add your own methods, and use a compact constructor for validation:

```java
public record Point(int x, int y) {
    public Point {                       // no parameter list needed
        if (x < 0 || y < 0)
            throw new IllegalArgumentException("Coordinates must not be negative");
    }

    public double distanceToOrigin() {
        return Math.sqrt(x * x + y * y);
    }
}
```

Records are a good fit for DTOs, returning multiple values from a method, map keys, and configuration values. When you need mutable state or complex inheritance, use a regular class.

## Java 17: Sealed Interfaces and Java 21 Pattern Matching

A sealed interface restricts which classes or subinterfaces can implement or extend it. Combined with `switch` pattern matching in Java 21, the compiler can check that every case is handled.

It's the opposite of default methods:

- **default**: Others can implement it, and you can still add methods without breaking them.
- **sealed**: You control every implementation, since only the types listed in `permits` can implement it.

### When You Need permits

| Where the implementations are | `permits` |
| --- | --- |
| In the same source file as the sealed interface | Optional; the compiler infers it |
| In different files | Required; they must be in the same module (or the same package if there's no module) |

```java
// Same file: permits can be omitted
public sealed interface Shape {
    record Circle(double r) implements Shape {}
    record Square(double side) implements Shape {}
}
```

```java
// Different files: permits is required
public sealed interface Shape permits Circle, Square {}
```

Every direct implementation of a sealed type must be marked `final`, `sealed`, or `non-sealed`. Records are implicitly `final` and need nothing extra, which makes **sealed interface + record** the most concise combination.

### With Java 21 switch and Record Patterns

```java
double area(Shape s) {
    return switch (s) {
        case Circle c          -> Math.PI * c.r() * c.r();
        case Square(double a)  -> a * a;
        // no default needed; the compiler knows these are the only two
    };
}
```

If you later add `Triangle` to `permits`, every `switch` that doesn't handle `Triangle` fails to compile, reminding you to add it.

## Comparison with Python

A Java record is closest to Python's `@dataclass(frozen=True)` or `typing.NamedTuple`:

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class Point:
    x: int
    y: int
```

| | Java record | Python dataclass |
| --- | --- | --- |
| Mutability | Always immutable | Mutable by default; immutable only with `frozen=True` |
| Inheritance | Can't extend or be extended | Can inherit freely |
| Flexibility | Fields are the constructor parameters, and all take part in `equals` | Supports default values, `default_factory`, and excluding fields from comparison |
| Auto-generated | Constructor, accessors, `equals`, `hashCode`, `toString` | `__init__`, `__repr__`, `__eq__` (plus `__hash__` when frozen) |

Java 21 record patterns correspond to Python 3.10's `match`:

```python
match shape:
    case Circle(r=r):
        ...
    case Square(side=a):
        ...
```

## Summary

- **Java 8 default methods**: add methods to a published interface without breaking existing implementations.
- **Java 9 private methods**: let default methods share internal logic without exposing helper methods.
- **Java 16 records**: declare an immutable data class in one line, and it can implement interfaces.
- **Java 17 sealed + Java 21 pattern matching**: limit which types can implement an interface, so the compiler can check that a `switch` handles every case.

The first two make interfaces easier to maintain when they're *open for others to implement*. The last two let interfaces serve as type-safe data models when *the set of implementations is fixed*.
