let Hooks = {};

function createTable(element, headers, data) {
  let table = document.createElement("table");
  let thead = document.createElement("thead");
  let tbody = document.createElement("tbody");

  let headerRow = document.createElement("tr");
  headers.forEach((header) => {
    let th = document.createElement("th");
    th.textContent = header;
    headerRow.appendChild(th);
  });
  thead.appendChild(headerRow);

  data.forEach((item) => {
    let row = document.createElement("tr");
    Object.values(item).forEach((value) => {
      let td = document.createElement("td");
      td.textContent = value;
      row.appendChild(td);
    });
    tbody.appendChild(row);
  });

  table.appendChild(thead);
  table.appendChild(tbody);
  element.appendChild(table);
}

Hooks.table = {
  mounted() {
    let tableData = JSON.parse(this.el.dataset.tableData);
    let tableHeaders = JSON.parse(this.el.dataset.tableHeaders);
    createTable(this.el, tableHeaders, tableData);
  },
};

Hooks.dateInput = {
  mounted() {
    flatpickr(this.el, {
      altInput: true,
      altFormat: "Y-m-d h:i K",
      dateFormat: "Z",
      enableTime: true,
      parseDate(dateString, format) {
        var wrongDate = new Date(dateString);
        var localizedDate = new Date(
          wrongDate.getTime() - wrongDate.getTimezoneOffset() * 60000
        );
        return localizedDate;
      },
    });
  },
};
export default Hooks;
