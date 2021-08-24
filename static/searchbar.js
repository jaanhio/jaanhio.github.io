const searchBar = document.getElementById("tag-searchbar");
const collections = document.getElementsByClassName("collection-content");

// perform filter logic only on collections page where the above elements are present
if (searchBar && collections) {
    // search event fires when input "x" clear button (on some browsers) is clicked or user finishes input
    // this logic is added specifically to handle just the input "x" button
    searchBar.addEventListener('search', event => {
        const searchVal = searchBar.value.toLowerCase();
        if (searchVal === "") {
            showAllContent(collections);
        }
    });
    
    searchBar.addEventListener('input', event => {
        const searchVal = searchBar.value.toLowerCase();
        if (searchVal === "") {
          showAllContent(collections);
        } else {
          showOnlyMatchingContent(searchVal, collections);
        }
    });
}

const showAllContent = (collections) => {
    Array.from(collections).forEach(collection => {
        collection.style.display = "block"
    });
}

const showOnlyMatchingContent = (searchVal, collections) => {
    showAllContent(collections);

    Array.from(collections).forEach(collection => {
        const { tags } = collection.dataset;
        if (!tags.includes(searchVal)) {
            collection.style.display = "none";
        }
    });
}