---
layout: post
title: 'Stop Using Links as Buttons: When to Use a, button, or input type="button"'
description: 'a, button, and input type="button" can all look like buttons, but they differ in semantics, keyboard interaction, form behavior, styling flexibility, and accessibility. Learn which HTML element to use and when.'
author: Mark_Mew
categories: [HTML]
tags: [html, button, accessibility]
keywords: [HTML, a, button, input, accessibility, semantic HTML]
lang: en
date: 2026-06-28
---

As web developers, we are all familiar with the `a`, `button`, and `input` HTML elements. CSS can make all three look like buttons, but a similar appearance does not mean they serve the same purpose.

Their differences go beyond whether they can contain an image. They also differ in where their content comes from, their default behavior, HTML semantics, CSS flexibility, and accessibility.

Start with the most important rule:

> **Use `a` to go somewhere. Use `button` to do something.**

An `input type="button"` can also perform an action, but it offers less flexibility in content and styling. Unless a project has a specific constraint, `button` is usually the better choice for new code.

## Quick Comparison

| Element | Primary Semantics | Content Source | Default Behavior | Can Contain HTML Elements? |
| --- | --- | --- | --- | --- |
| `a` | Navigate to another URL or document location | Content between the opening and closing tags | Navigate to its `href` | Yes, but it cannot contain other interactive elements |
| `button` | Perform an action | Content between the opening and closing tags | May submit a form when used inside one | Yes: text, images, SVG, `span`, and other phrasing content |
| `input type="button"` | Perform an action | The `value` attribute | No default action | No; it is a void element |

## Difference 1: The HTML Content They Can Contain

The most obvious difference is that a `button` can use HTML content to build its label, while an `input type="button"` can display only a plain-text label.

```html
<button type="button">
  <img src="save.svg" alt="">
  <span>Save</span>
</button>
```

A `button` can contain text, images, `span`, `strong`, or SVG elements. This makes it suitable for icon buttons and labels with multiple visual styles.

Strictly speaking, however, a `button` cannot contain “any HTML.” Its content is primarily phrasing content, and it cannot contain interactive elements such as `a`, another `button`, or `input`.

```html
<!-- Invalid: do not put an interactive element inside a button -->
<button type="button">
  Save
  <a href="/help">Help</a>
</button>
```

An `input`, on the other hand, is a void element. It has no closing tag and cannot contain child elements:

```html
<input type="button" value="Save">
```

The following markup does not conform to the HTML specification:

```html
<!-- Invalid: an input cannot contain child elements -->
<input type="button">
  <img src="save.svg" alt="">
  Save
</input>
```

One commonly overlooked detail is that `a` is not limited to text either. It can also contain images, `span`, `strong`, SVG, or even form an entire clickable card:

```html
<a href="/settings" class="link-card">
  <img src="settings.svg" alt="">
  <span>
    <strong>System Settings</strong>
    <small>Manage your account and notifications</small>
  </span>
</a>
```

The `a` element uses a transparent content model, so the content it may contain also depends on its surrounding context. However, it cannot contain another `a` or interactive elements such as `button` and `input`, and its descendants cannot have a `tabindex` attribute.

## Difference 2: Where the Displayed Content Comes From

The visible content of `a` and `button` comes from the DOM content between their opening and closing tags:

```html
<a href="/settings">System Settings</a>
<button type="button">Save</button>
```

Their labels can also be composed of multiple child elements:

```html
<button type="button">
  <svg aria-hidden="true"><!-- icon --></svg>
  <span>Save Changes</span>
</button>
```

In contrast, the text displayed by `input type="button"` comes from its `value` attribute:

```html
<input type="button" value="Save Changes">
```

That also changes how their labels are updated with JavaScript:

```javascript
document.querySelector("button").textContent = "Processing";
document.querySelector('input[type="button"]').value = "Processing";
```

This is one reason why `button` is easier to extend: its label is DOM content, so icons, text, loading states, and other visual elements can be updated independently. An `input` has only its text-based `value`.

## Difference 3: Their Default Behavior

Browsers provide different default behavior when these elements are activated.

### The Default Behavior of a Is Navigation

An `a` with an `href` is a hyperlink. Activating it navigates to another page, website, file, or location in the same document:

```html
<a href="/settings">Go to Settings</a>
<a href="#comments">View Comments</a>
<a href="/report.pdf" download>Download Report</a>
```

### A button May Submit a Form

Inside a form, a `button` without an explicit `type` will usually become a submit button. A button intended only to open a dialog or preview some content may therefore submit the form by accident.

```html
<form>
  <!-- Perform an ordinary action without submitting the form -->
  <button type="button">Preview</button>

  <!-- Submit the form -->
  <button type="submit">Save</button>

  <!-- Reset the form; less common in practice -->
  <button type="reset">Reset</button>
</form>
```

Even when a button is not currently inside a form, explicitly writing `type="button"` prevents surprises if the DOM structure changes later.

### input type="button" Has No Default Action

An `input type="button"` does not navigate or submit a form by itself. It usually needs JavaScript to do something:

```html
<input type="button" value="Open Dialog" onclick="openDialog()">
```

Do not confuse it with `input type="submit"`:

```html
<!-- An ordinary button with no default action -->
<input type="button" value="Preview">

<!-- Submit the form -->
<input type="submit" value="Save">
```

## Difference 4: Their HTML Semantics

The most important difference between these elements is not how they look, but what they communicate to the browser.

### a Means “Go Somewhere”

If activation changes the URL, opens another page, moves to a different location in a document, or downloads a file, use an `a` with an `href`.

Links also provide native browser capabilities: users can open them in a new tab, copy their URLs, and search engines can understand the relationships between pages.

Do not use an `a` without an `href` as a fake button:

```html
<!-- Not recommended -->
<a onclick="openDialog()">Open Dialog</a>

<!-- Correct semantics -->
<button type="button" onclick="openDialog()">Open Dialog</button>
```

Using `href="#"` is not a good substitute either. It still represents navigation and may change the URL or jump the page back to the top.

### button and input type="button" Mean “Perform an Action”

Opening a dialog, toggling a menu, adding an item to a cart, and saving data are all actions on the current page, so they should use buttons.

Both `button` and `input type="button"` can semantically represent a button. However, `button` supports richer content and is generally more practical in new code. An `input type="button"` remains useful in legacy systems, tool-generated forms, or simple cases that require only a text label.

Conversely, using a `button` with JavaScript to simulate navigation is also discouraged. It removes native link features such as opening a destination in a new tab or copying its address.

In one sentence:

> **Link goes somewhere. Button does something.**

## Difference 5: CSS and Layout Flexibility

CSS can make all three elements look nearly identical, but their browser defaults and internal styling flexibility still differ.

An `a` is normally displayed as an inline text link, while `button` and `input` receive native form-control styles from the browser or operating system. In practice, a shared style often normalizes their font, border, background, and spacing:

```css
.button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding: 0.5rem 1rem;
  border: 1px solid transparent;
  border-radius: 0.375rem;
  font: inherit;
  color: inherit;
  text-decoration: none;
  cursor: pointer;
}
```

```html
<a class="button" href="/settings">Go to Settings</a>
<button class="button" type="button">Save</button>
<input class="button" type="button" value="Preview">
```

The real difference appears in their internal layout. Both `a` and `button` can contain separate elements for icons and text, which can then be arranged with Flexbox, Grid, or individual classes. An `input` has no child elements, so only the control itself can be styled; its internal text and icons cannot be laid out independently.

If a design needs an icon, loading spinner, two lines of text, or other compound content, `button` is usually a better choice than `input type="button"`.

## Difference 6: Accessibility

When native HTML elements are used correctly, the browser provides the appropriate role, focus behavior, and keyboard interaction:

- An `a` with an `href` is exposed as a link and is typically activated with Enter.
- `button` and `input type="button"` are exposed as buttons and are typically activated with Enter or Space.
- `button` and `input` support the native `disabled` attribute.
- `a` does not have a `disabled` attribute.

```html
<button type="button" disabled>Processing</button>
<input type="button" value="Processing" disabled>
```

Adding `aria-disabled="true"` to an `a` only communicates the disabled state through the accessibility tree. It does not automatically prevent navigation or click events. If a control is fundamentally an action that can be disabled, it is usually better represented by a `button` in the first place.

### Icon Buttons Still Need an Understandable Name

An icon-only button without visible text should have a clear accessible name:

```html
<button type="button" aria-label="Close dialog">
  <svg aria-hidden="true"><!-- close icon --></svg>
</button>
```

If an icon is accompanied by text that already explains the action, a decorative image can use an empty `alt` value so that screen readers do not announce the same information twice:

```html
<button type="button">
  <img src="save.svg" alt="">
  Save
</button>
```

Do not simulate a button with a `div` or `span`. Otherwise, you must manually recreate focus behavior, keyboard events, and ARIA semantics—and it is easy to miss something.

```html
<!-- Not recommended -->
<div class="button" onclick="save()">Save</div>

<!-- Recommended -->
<button type="button" onclick="save()">Save</button>
```

When a native HTML element already solves the problem, there is no need to reinvent a less usable button.

## Which One Should You Use?

Use this checklist to decide:

1. Does activation change the current URL, navigate to another page, or download a resource? Use `a href="..."`.
2. Does it perform an action on the current page? Use `button`.
3. Does the button submit a form? Use `button type="submit"`.
4. Is it an ordinary action that should not submit a form? Use `button type="button"`.
5. Are you constrained by a legacy system or need only a plain-text form control? Only then consider `input type="button"`.

Choose the correct HTML semantics first, then use CSS to control the appearance. This makes the code easier to maintain and allows keyboards, assistive technologies, and search engines to understand the page correctly.

## References

- [HTML Living Standard: The `a` element](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-a-element)
- [HTML Living Standard: The `button` element](https://html.spec.whatwg.org/multipage/form-elements.html#the-button-element)
- [HTML Living Standard: The `input` element](https://html.spec.whatwg.org/multipage/input.html#the-input-element)
