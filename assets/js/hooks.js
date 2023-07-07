let Hooks = {};

function createChart(ctx, chartType, chartData, label, options) {
  let backgroundColor, borderColor;

  if (chartType === "bar") {
    backgroundColor = "#109654";
    borderColor = "rgb(72, 72, 72)";
  } else if (chartType === "pie") {
    backgroundColor = ["#109654", "#23d4c2", "#ffc600"];
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
    options: options,
  });
}

Hooks.barChart = {
  mounted() {
    var ctx = this.el.getContext("2d");
    let label = this.el.dataset.label;
    let chartData = JSON.parse(this.el.dataset.chartData);
    createChart(ctx, "bar", chartData, label);
  },
};

// creating a pie chart
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
  }
}

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
