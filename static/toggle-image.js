const zoomableImgs = document.getElementsByClassName("zoomable");
const head = document.getElementsByTagName("head")[0];

let isToggled = false

const setDivStyleAndAttr = (div) => {
    div.style.display = 'flex'
    div.style.position = 'fixed'
    div.style.height = '100%'
    div.style.width = '100%'
    div.style.justifyContent = 'center'
    div.style.alignItems = 'center'
    div.style.backgroundColor = 'rgba(0,0,0,0.4)'

    div.setAttribute('id', 'overlay-div')
}

const setImgStyle = (img) => {
    img.style.maxWidth = '90%'
    img.style.cursor = 'zoom-out'
}

for (const img of zoomableImgs) {
    img.addEventListener('click', (event) => {
        const imgSrc = event.target.attributes.src.value;
        
        const overlayDiv = document.createElement('div')
        setDivStyleAndAttr(overlayDiv)

        overlayDiv.addEventListener('click', (overlayEvent) => {
            console.log('overlay', overlayEvent)
        })

        const overlayImg = document.createElement('img')
        overlayImg.src = imgSrc
        setImgStyle(overlayImg)
        
        overlayDiv.append(overlayImg)
        head.after(overlayDiv)

        isToggled = true
    })    
}