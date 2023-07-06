let Hooks = {};

Hooks.chart = {
  mounted() {
    var ctx = this.el.getContext("2d");
    let label = this.el.dataset.label;
    let chartData = JSON.parse(this.el.dataset.chartData);
    var chart = new Chart(ctx, {
      // The type of chart we want to create
      type: "bar",
      // The data for our dataset
      data: {
        // date_labels are the default last 7 day dates
        labels: chartData.labels,
        datasets: [
          {
            label: label,
            backgroundColor: "rgb(17, 150, 86)",
            borderColor: "rgb(255, 99, 132)",
            // data is the data trend in last 7 day
            data: chartData.data,
          },
        ],
      },
      // Configuration options go here
      options: {},
    });
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

// creating a pie chart
Hooks.optin_chart = { 
  mounted() { 
    var ctx = this.el.getContext("2d");
    let optin = JSON.parse(this.el.dataset.chartDataOptin);
    let optout = JSON.parse(this.el.dataset.chartDataOptout);
    let nonopt = JSON.parse(this.el.dataset.chartDataNonopt);
    var chart = new Chart(ctx, {
      type: "pie",
      data: {
        labels: ["Opted-In", "Opted-Out", "Not-Opted"],
        datasets: [ {
          label: "Optin",
          data: [optin, optout, nonopt],
          backgroundColor: ["#109654", "#23d4c2", "#ffc600"],
        },],
      },
      options: {
        title: {
          text: "Optin Rate",
          fontSize: 20,
        },
        legend: {
          display: true,
          position: "right",
        },
      },
    });
  }
}
export default Hooks;
