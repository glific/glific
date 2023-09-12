let Hooks = {};

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

Hooks.download = {
  mounted() {
    this.handleEvent("download-file", (event) => {
      var element = document.createElement("a");
      element.setAttribute(
        "href",
        "data:csv/plain;charset=utf-8,%EF%BB%BF" +
          encodeURIComponent(event.data)
      );
      element.setAttribute("download", event.filename);
      element.style.display = "none";
      document.body.appendChild(element);
      element.click();
      document.body.removeChild(element);
    });
  },
};

Hooks.dateRestrict = {
  mounted() {
    let today = new Date().toISOString().split("T")[0];
    document.getElementById("start_day").setAttribute("max", today);
    document.getElementById("end_day").setAttribute("max", today);

    this.el.addEventListener("change", (e) => {
      let startInput = document.getElementById("start_day");
      let endInput = document.getElementById("end_day");
      if (e.target.name === "start_day") {
        endInput.setAttribute("min", startInput.value);
      }
    });
  },
};

export default Hooks;
