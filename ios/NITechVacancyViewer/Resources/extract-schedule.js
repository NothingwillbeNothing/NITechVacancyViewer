(function () {
    "use strict";
    const tables = Array.from(document.querySelectorAll(".kyuko-shisetsu-nofixed"));
    if (!tables.length || tables.length > 7) {
        throw new Error("Reservation tables not found");
    }
    return JSON.stringify({
        days: tables.map(function (table) {
            // Some Campus Square variants expose the full date in an attribute.
            // Otherwise the native decoder uses today's campus date plus offset,
            // matching the upstream Android application's week view.
            const rawDate = table.getAttribute("data-date");
            const date = rawDate && /^\d{4}-\d{2}-\d{2}$/.test(rawDate) ? rawDate : null;
            const body = table.querySelector("tbody");
            if (!body) { throw new Error("Missing reservation table body"); }
            const rows = Array.from(body.rows || body.querySelectorAll("tr"));
            const rooms = rows.map(function (row) {
                const name = row.querySelector(".kyuko-shi-shisetsunm");
                if (!name) { return null; } // Skip table headings only.
                const cell = row.querySelector('[valign="top"]');
                if (!cell) { throw new Error("Missing reservation cell"); }
                return {
                    name: (name.textContent || "").trim(),
                    events: Array.from(cell.querySelectorAll(".kyuko-shi-jugyo"))
                        .map(function (event) {
                            return { text: (event.textContent || "").replace(/\s+/g, " ").trim() };
                        })
                };
            }).filter(Boolean);
            if (!rooms.length) { throw new Error("Empty reservation table"); }
            return { date: date, rooms: rooms };
        })
    });
})()
