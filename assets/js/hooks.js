let Hooks = {};

Hooks.chart = {
  mounted() {
    var ctx = this.el.getContext("2d");
    let label = this.el.dataset.label;
    var chart = new Chart(ctx, {
      // The type of chart we want to create
      type: "bar",
      // The data for our dataset
      data: {
        labels: [
          "06-01-23",
          "07-01-23",
          "08-01-23",
          "09-01-23",
          "10-01-23",
          "11-01-23",
          "12-01-23",
        ],
        datasets: [
          {
            label: label,
            backgroundColor: "rgb(255, 99, 132)",
            borderColor: "rgb(255, 99, 132)",
            data: [0, 10, 5, 2, 20, 30, 45],
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

export default Hooks;
