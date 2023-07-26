let Hooks = {};

function createChart(ctx, chartType, chartData, label, options) {
  let backgroundColor,
    borderColor,
    datasets = [];

  borderColor = "#F9F7F4";
  backgroundColor = ["#129656", "#93A29B", "#EBEDEC", "#B5D8C7"];

  if (chartType === "bar") {
    if (Array.isArray(chartData.data[0])) {
      for (let i = 0; i < chartData.data.length; i++) {
        datasets.push({
          label: chartData.label[i],
          backgroundColor: backgroundColor[i],
          borderColor: borderColor,
          data: chartData.data[i],
        });
      }
    } else {
      datasets = [
        {
          label: label,
          backgroundColor: backgroundColor[0],
          borderColor: borderColor,
          data: chartData.data,
        },
      ];
    }
  } else {
    datasets = [
      {
        label: label,
        data: chartData.data,
        backgroundColor: backgroundColor,
      },
    ];
  }

  return new Chart(ctx, {
    type: chartType,
    data: {
      labels: chartData.labels,
      datasets: datasets,
    },
    options,
  });
}

function createTable(element, headers, data) {
  let table = document.createElement("table");
  let thead = document.createElement("thead");
  let tbody = document.createElement("tbody");

  // Create table header (thead)
  let headerRow = document.createElement("tr");
  headers.forEach((header) => {
    let th = document.createElement("th");
    th.textContent = header;
    headerRow.appendChild(th);
  });
  thead.appendChild(headerRow);

  // Create table rows (tbody)
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

Hooks.barChart = {
  mounted() {
    var ctx = this.el.getContext("2d");
    let label = this.el.dataset.label;
    let chartData = JSON.parse(this.el.dataset.chartData);
    createChart(ctx, "bar", chartData, label);
  },
};

Hooks.pieChart = {
  mounted() {
    var ctx = this.el.getContext("2d");
    let label = this.el.dataset.label;
    let chartData = JSON.parse(this.el.dataset.chartData);
    createChart(ctx, "pie", chartData, label, {
      legend: {
        display: true,
        position: "right",
      },
    });
  },
};

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
