let Hooks = {};

function createChart(ctx, chartType, chartData, label) {
  let backgroundColor, borderColor;

  if (chartType === "bar") {
    backgroundColor = "rgb(17, 150, 86)";
    borderColor = "rgb(72, 72, 72)";
  } else if (chartType === "pie") {
    backgroundColor = ["rgb(58,168,114)", "rgb(13,108,61)"];
    borderColor = "rgb(72, 72, 72)";
  }

  return new Chart(ctx, {
    // The type of chart we want to create
    type: chartType,
    data: {
      labels: chartData.labels,
      // The data for our dataset
      datasets: [
        {
          label: label,
          backgroundColor: backgroundColor,
          borderColor: borderColor,
          data: chartData.data,
        },
      ],
    },
    // Configuration options go here
    options: {},
  });
}

Hooks.chart = {
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
    createChart(ctx, "pie", chartData, label);
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
