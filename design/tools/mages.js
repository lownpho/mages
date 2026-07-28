/* Shared browser for the design views.
 *
 * Every page is the same thing: filter a list of records by chip facets and a
 * search box, sort it, draw a card per survivor. Only the facets and the card
 * differ, so those are all a page supplies.
 *
 *   MAGES.browse({
 *     items:  DATA.spells,
 *     noun:   "spells",
 *     facets: [{ key: "category", label: "Type", vals: s => [s.category] }],
 *     search: s => s.name + " " + s.description,
 *     sorts:  { name: (a, b) => a.name.localeCompare(b.name) },
 *     card:   s => someElement,
 *   });
 *
 * Expects the page to carry #q, #sort, #facets, #grid, #empty, #count, #reset,
 * and to have loaded data.js (which defines window.MAGES) first.
 */
(function () {
  "use strict";

  var M = window.MAGES;

  /** el("div", "card", "text") / el("div", "card", [child, child]) */
  function el(tag, cls, body) {
    var node = document.createElement(tag);
    if (cls) node.className = cls;
    if (body === undefined || body === null) return node;
    if (Array.isArray(body)) body.forEach(function (c) { if (c) node.appendChild(c); });
    else if (typeof body === "object") node.appendChild(body);
    else node.textContent = body;
    return node;
  }

  /** Ordinal position in an explicit order list; unlisted values sort last. */
  function rank(order, value) {
    if (!order) return -1;
    var i = order.indexOf(value);
    return i < 0 ? 999 : i;
  }

  /** An icon: its region cut out of the sheet at native size, then scaled up.
   *
   * Scaling the whole cut-out rather than the background keeps this independent
   * of the sheet's dimensions, which the dataset doesn't carry. Pixel-perfect
   * either way — the transform is a whole-number zoom on a pixelated image.
   */
  function sprite(icon, scale) {
    if (!icon) return null;
    var s = scale || 4;
    var r = icon.region || [0, 0, 16, 16];
    var cut = el("div", "sprite");
    cut.style.width = r[2] + "px";
    cut.style.height = r[3] + "px";
    cut.style.backgroundImage = 'url("' + icon.url + '")';
    cut.style.backgroundPosition = -r[0] + "px " + -r[1] + "px";
    cut.style.transform = "scale(" + s + ")";

    var box = el("div", "sprite-box", cut);
    box.style.width = r[2] * s + "px";
    box.style.height = r[3] * s + "px";
    return box;
  }

  function browse(cfg) {
    var items = cfg.items;
    var facets = cfg.facets || [];
    var active = {};
    facets.forEach(function (f) { active[f.key] = new Set(); });

    var qEl = document.getElementById("q");
    var sortEl = document.getElementById("sort");
    var gridEl = document.getElementById("grid");
    var emptyEl = document.getElementById("empty");
    var countEl = document.getElementById("count");
    var facetsEl = document.getElementById("facets");

    // Chips: every value actually present, in the facet's declared order.
    facets.forEach(function (f) {
      var present = {};
      items.forEach(function (it) {
        f.vals(it).forEach(function (v) { if (v !== "" && v != null) present[v] = true; });
      });
      var vals = Object.keys(present);
      vals.sort(function (a, b) {
        var d = rank(f.order, a) - rank(f.order, b);
        if (f.order && d !== 0) return d;
        var na = parseFloat(a), nb = parseFloat(b);
        if (!isNaN(na) && !isNaN(nb) && String(na) === a && String(nb) === b) return na - nb;
        return a.localeCompare(b);
      });
      if (vals.length < 2) return;          // a facet with one value filters nothing

      var wrap = el("div", "facet", el("span", "flabel", f.label));
      vals.forEach(function (v) {
        var chip = el("button", "chip", f.chipText ? f.chipText(v) : v);
        chip.type = "button";
        chip.setAttribute("aria-pressed", "false");
        chip.addEventListener("click", function () {
          var on = chip.getAttribute("aria-pressed") === "true";
          chip.setAttribute("aria-pressed", on ? "false" : "true");
          if (on) active[f.key].delete(v); else active[f.key].add(v);
          render();
        });
        wrap.appendChild(chip);
      });
      facetsEl.appendChild(wrap);
    });

    function matches(it) {
      for (var i = 0; i < facets.length; i++) {
        var sel = active[facets[i].key];
        if (sel.size === 0) continue;
        var vals = facets[i].vals(it).map(String);
        if (!vals.some(function (v) { return sel.has(v); })) return false;
      }
      var q = qEl ? qEl.value.trim().toLowerCase() : "";
      return !q || String(cfg.search(it)).toLowerCase().indexOf(q) >= 0;
    }

    function render() {
      var list = items.filter(matches);
      var mode = sortEl ? sortEl.value : "";
      if (cfg.sorts && cfg.sorts[mode]) list.sort(cfg.sorts[mode]);
      gridEl.innerHTML = "";
      list.forEach(function (it) { gridEl.appendChild(cfg.card(it)); });
      if (emptyEl) emptyEl.hidden = list.length !== 0;
      if (countEl) countEl.textContent = list.length + " / " + items.length + " " + cfg.noun;
    }

    if (qEl) qEl.addEventListener("input", render);
    if (sortEl) sortEl.addEventListener("change", render);
    var resetEl = document.getElementById("reset");
    if (resetEl) {
      resetEl.addEventListener("click", function () {
        if (qEl) qEl.value = "";
        facets.forEach(function (f) { active[f.key].clear(); });
        Array.prototype.forEach.call(facetsEl.querySelectorAll(".chip"), function (c) {
          c.setAttribute("aria-pressed", "false");
        });
        render();
      });
    }

    render();
    return render;
  }

  M.el = el;
  M.sprite = sprite;
  M.browse = browse;
})();
