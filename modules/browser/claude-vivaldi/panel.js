chrome.tabs.query({ active: true, currentWindow: true }).then(([tab]) => {
  location.replace(`sidepanel.html?tabId=${tab.id}`);
});
