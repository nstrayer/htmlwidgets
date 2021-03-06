#' @export
print.htmlwidget <- function(x, ..., view = interactive()) {

  # if we have a viewer then forward viewer pane height (if any)
  viewer <- getOption("viewer")
  if (!is.null(viewer)) {
    viewerFunc <- function(url) {

      # get the requested pane height (it defaults to NULL)
      paneHeight <- x$sizingPolicy$viewer$paneHeight

      # convert maximize to -1 for compatibility with older versions of rstudio
      # (newer versions convert 'maximize' to -1 interally, older versions
      # will simply ignore the height if it's less than zero)
      if (identical(paneHeight, "maximize"))
        paneHeight <- -1

      # call the viewer
      viewer(url, height = paneHeight)
    }
  } else {
    viewerFunc <- utils::browseURL
  }

  # call html_print with the viewer
  html_print(htmltools::as.tags(x, standalone=TRUE), viewer = if (view) viewerFunc)

  # return value
  invisible(x)
}

#' @export
print.suppress_viewer <- function(x, ..., view = interactive()) {
  html_print(htmltools::as.tags(x, standalone=TRUE), viewer = if (view) browseURL)
  invisible(x)
}

#' @method as.tags htmlwidget
#' @export
as.tags.htmlwidget <- function(x, standalone = FALSE) {
  toHTML(x, standalone = standalone)
}

#' Prepend/append extra HTML content to a widget
#'
#' Use these functions to attach extra HTML content (primarily JavaScript and/or
#' CSS styles) to a widget, for rendering in standalone mode (i.e. printing at
#' the R console) or in a knitr document. These functions are NOT supported when
#' running in a Shiny widget rendering function, and will result in a warning if
#' used in that context. Multiple calls are allowed, and later calls do not undo
#' the effects of previous calls.
#'
#' @param x An HTML Widget object
#' @param ... Valid \link[htmltools]{tags}, text, and/or
#'   \code{\link[htmltools]{HTML}}, or lists thereof.
#' @return A modified HTML Widget object.
#'
#' @export
prependContent <- function(x, ...) {
  x$prepend <- c(x$prepend, list(...))
  x
}

#' @rdname prependContent
#' @export
appendContent <- function(x, ...) {
  x$append <- c(x$append, list(...))
  x
}

#' Execute custom JavaScript code after rendering
#'
#' Use this function to supplement the widget's built-in JavaScript rendering
#' logic with additional custom JavaScript code, just for this specific widget
#' object.
#'
#' @param x An HTML Widget object
#' @param jsCode Character vector containing JavaScript code (see Details)
#' @param data An additional argument to pass to the \code{jsCode} function.
#'   This can be any R object that can be serialized to JSON. If you have
#'   multiple objects to pass to the function, use a named list.
#' @return The modified widget object
#'
#' @details The \code{jsCode} parameter must be a valid JavaScript expression
#'   that returns a function.
#'
#'   The function will be invoked with three arguments: the first is the widget's
#'   main HTML element, and the second is the data to be rendered (the \code{x}
#'   parameter in \code{createWidget}). The third argument is the JavaScript
#'   equivalent of the R object passed into \code{onRender} as the \code{data}
#'   argument; this is an easy way to transfer e.g. data frames without having
#'   to manually do the JSON encoding.
#'
#'   When the function is invoked, the \code{this} keyword will refer to the
#'   widget instance object.
#'
#' @seealso \code{\link{onStaticRenderComplete}}, for writing custom JavaScript
#'   that involves multiple widgets.
#'
#' @examples
#' \dontrun{
#' library(leaflet)
#'
#' # This example uses browser geolocation. RStudio users:
#' # this won't work in the Viewer pane; try popping it
#' # out into your system web browser.
#' leaflet() %>% addTiles() %>%
#'   onRender("
#'     function(el, x) {
#'       // Navigate the map to the user's location
#'       this.locate({setView: true});
#'     }
#'   ")
#'
#'
#' # This example shows how you can make an R data frame available
#' # to your JavaScript code.
#'
#' meh <- "&#x1F610;";
#' yikes <- "&#x1F628;";
#'
#' df <- data.frame(
#'   lng = quakes$long,
#'   lat = quakes$lat,
#'   html = ifelse(quakes$mag < 5.5, meh, yikes),
#'   stringsAsFactors = FALSE
#' )
#'
#' leaflet() %>% addTiles() %>%
#'   fitBounds(min(df$lng), min(df$lat), max(df$lng), max(df$lat)) %>%
#'   onRender("
#'     function(el, x, data) {
#'       for (var i = 0; i < data.lng.length; i++) {
#'         var icon = L.divIcon({className: '', html: data.html[i]});
#'         L.marker([data.lat[i], data.lng[i]], {icon: icon}).addTo(this);
#'       }
#'     }
#'   ", data = df)
#' }
#'
#' @export
onRender <- function(x, jsCode, data = NULL) {
  addHook(x, "render", jsCode, data)
}

addHook <- function(x, hookName, jsCode, data = NULL) {
  if (length(jsCode) == 0)
    return(x)

  if (length(jsCode) > 1)
    jsCode <- paste(jsCode, collapse = "\n")

  x$jsHooks[[hookName]] <- c(x$jsHooks[[hookName]], list(list(code = jsCode, data = data)))
  x
}


toHTML <- function(x, standalone = FALSE, knitrOptions = NULL) {

  sizeInfo <- resolveSizing(x, x$sizingPolicy, standalone = standalone, knitrOptions = knitrOptions)

  if (!is.null(x$elementId))
    id <- x$elementId
  else
    id <- paste("htmlwidget", createWidgetId(), sep="-")

  w <- validateCssUnit(sizeInfo$width)
  h <- validateCssUnit(sizeInfo$height)

  # create a style attribute for the width and height
  style <- paste(
    "width:", w, ";",
    "height:", h, ";",
    sep = "")

  x$id <- id

  container <- if (isTRUE(standalone)) {
    function(x) {
      div(id="htmlwidget_container", x)
    }
  } else {
    identity
  }

  html <- htmltools::tagList(
    container(
      htmltools::tagList(
        x$prepend,
        widget_html(
          name = class(x)[1],
          package = attr(x, "package"),
          id = id,
          style = style,
          class = paste(class(x)[1], "html-widget"),
          width = sizeInfo$width,
          height = sizeInfo$height
        ),
        x$append
      )
    ),
    widget_data(x, id),
    if (!is.null(sizeInfo$runtime)) {
      tags$script(type="application/htmlwidget-sizing", `data-for` = id,
        toJSON(sizeInfo$runtime)
      )
    }
  )
  html <- htmltools::attachDependencies(html,
    c(widget_dependencies(class(x)[1], attr(x, 'package')),
      x$dependencies)
  )

  htmltools::browsable(html)

}


widget_html <- function(name, package, id, style, class, inline = FALSE, ...){

  # attempt to lookup custom html function for widget
  fn <- tryCatch(get(paste0(name, "_html"),
                     asNamespace(package),
                     inherits = FALSE),
                 error = function(e) NULL)

  # call the custom function if we have one, otherwise create a div
  if (is.function(fn)) {
    fn(id = id, style = style, class = class, ...)
  } else if (inline) {
    tags$span(id = id, style = style, class = class)
  } else {
    tags$div(id = id, style = style, class = class)
  }
}

widget_dependencies <- function(name, package){
  getDependency(name, package)
}

# Generates a <script type="application/json"> tag with the JSON-encoded data,
# to be picked up by htmlwidgets.js for static rendering.
widget_data <- function(x, id, ...){
  # It's illegal for </script> to appear inside of a script tag, even if it's
  # inside a quoted string. Fortunately we know that in JSON, the only place
  # the '<' character can appear is inside a quoted string, where a Unicode
  # escape has the same effect, without confusing the browser's parser. The
  # repro for the bug this gsub fixes is to have the string "</script>" appear
  # anywhere in the data/metadata of a widget--you will get a syntax error
  # instead of a properly rendered widget.
  #
  # Another issue is that if </body></html> appears inside a quoted string,
  # then when pandoc coverts it with --self-contained, the escaping gets messed
  # up. There may be other patterns that trigger this behavior, so to be safe
  # we can replace all instances of "</" with "\\u003c/".
  payload <- toJSON(createPayload(x))
  payload <- gsub("</", "\\u003c/", payload, fixed = TRUE)
  tags$script(type = "application/json", `data-for` = id, HTML(payload))
}

#' Create an HTML Widget
#'
#' Create an HTML widget based on widget YAML and JavaScript contained within
#' the specified package.
#'
#' For additional details on developing widgets, see package vignettes:
#' \code{vignette("develop_intro", package = "htmlwidgets")}.
#'
#' @param name Widget name (should match the base name of the YAML and
#'   JavaScript files used to implement the widget)
#' @param x Widget instance data (underlying data to render and options that
#'   govern how it's rendered). This value will be converted to JSON using
#'   \code{\link[jsonlite]{toJSON}} and made available to the widget's
#'   JavaScript \code{renderValue} function.
#' @param width Fixed width for widget (in css units). The default is
#'   \code{NULL}, which results in intelligent automatic sizing based on the
#'   widget's container.
#' @param height Fixed height for widget (in css units). The default is
#'   \code{NULL}, which results in intelligent automatic sizing based on the
#'   widget's container.
#' @param sizingPolicy Options that govern how the widget is sized in various
#'   containers (e.g. a standalone browser, the RStudio Viewer, a knitr figure,
#'   or a Shiny output binding). These options can be specified by calling the
#'   \code{\link{sizingPolicy}} function.
#' @param package Package where the widget is defined (defaults to the widget
#'   name).
#' @param dependencies Additional widget HTML dependencies (over and above those
#'   defined in the widget YAML). This is useful for dynamic dependencies that
#'   only exist when selected widget options are enabled (e.g. sets of map tiles
#'   or projections).
#' @param elementId Use an explicit element ID for the widget (rather than an
#'   automatically generated one). Useful if you have other JavaScript that
#'   needs to explicitly discover and interact with a specific widget instance.
#' @param preRenderHook A function to be run on the widget, just prior to
#'   rendering. It accepts the entire widget object as input, and should return
#'   a modified widget object.
#'
#' @return An object of class \code{htmlwidget} that will intelligently print
#'   itself into HTML in a variety of contexts including the R console, within R
#'   Markdown documents, and within Shiny output bindings.
#' @export
createWidget <- function(name,
                         x,
                         width = NULL,
                         height = NULL,
                         sizingPolicy = htmlwidgets::sizingPolicy(),
                         package = name,
                         dependencies = NULL,
                         elementId = NULL,
                         preRenderHook = NULL) {
  # Turn single dependency object into list of dependencies, if necessary
  if (inherits(dependencies, "html_dependency"))
    dependencies <- list(dependencies)
  structure(
    list(x = x,
         width = width,
         height = height,
         sizingPolicy = sizingPolicy,
         dependencies = dependencies,
         elementId = elementId,
         preRenderHook = preRenderHook,
         jsHooks = list()),
    class = c(name,
              if (sizingPolicy$viewer$suppress) "suppress_viewer",
              "htmlwidget"),
    package = package
  )
}


#' Shiny bindings for HTML widgets
#'
#' Helpers to create output and render functions for using HTML widgets within
#' Shiny applications and interactive Rmd documents.
#'
#' @param outputId output variable to read from
#' @param name Name of widget to create output binding for
#' @param width,height Must be a valid CSS unit (like \code{"100\%"},
#'   \code{"400px"}, \code{"auto"}) or a number, which will be coerced to a
#'   string and have \code{"px"} appended.
#' @param package Package containing widget (defaults to \code{name})
#' @param inline use an inline (\code{span()}) or block container (\code{div()})
#' for the output
#' @param outputFunction Shiny output function corresponding to this render
#'   function.
#' @param reportSize Should the widget's container size be reported in the
#'   shiny session's client data?
#' @param expr An expression that generates an HTML widget
#' @param env The environment in which to evaluate \code{expr}.
#' @param quoted Is \code{expr} a quoted expression (with \code{quote()})? This
#'   is useful if you want to save an expression in a variable.
#'
#' @return An output or render function that enables the use of the widget
#'   within Shiny applications.
#'
#' @details These functions are delegated to from within your widgets own shiny
#'   output and render functions. The delegation is boilerplate and always works
#'   the same for all widgets (see example below).
#'
#' @examples
#' # shiny output binding for a widget named 'foo'
#' fooOutput <- function(outputId, width = "100%", height = "400px") {
#'   htmlwidgets::shinyWidgetOutput(outputId, "foo", width, height)
#' }
#'
#' # shiny render function for a widget named 'foo'
#' renderFoo <- function(expr, env = parent.frame(), quoted = FALSE) {
#'   if (!quoted) { expr <- substitute(expr) } # force quoted
#'   htmlwidgets::shinyRenderWidget(expr, fooOutput, env, quoted = TRUE)
#' }
#' @name htmlwidgets-shiny
#'
#' @export
shinyWidgetOutput <- function(outputId, name, width, height, package = name,
                              inline = FALSE, reportSize = FALSE) {

  checkShinyVersion()
  # generate html
  html <- htmltools::tagList(
    widget_html(name, package, id = outputId,
      class = paste0(name, " html-widget html-widget-output", if (reportSize) " shiny-report-size"),
      style = sprintf("width:%s; height:%s; %s",
        htmltools::validateCssUnit(width),
        htmltools::validateCssUnit(height),
        if (inline) "display: inline-block;" else ""
      ), width = width, height = height
    )
  )

  # attach dependencies
  dependencies = widget_dependencies(name, package)
  htmltools::attachDependencies(html, dependencies)
}


#' @rdname htmlwidgets-shiny
#' @export
shinyRenderWidget <- function(expr, outputFunction, env, quoted) {

  checkShinyVersion()
  # generate a function for the expression
  func <- shiny::exprToFunction(expr, env, quoted)

  # create the render function
  renderFunc <- function() {
    instance <- func()
    if (!is.null(instance$elementId)) {
      warning("Ignoring explicitly provided widget ID \"",
        instance$elementId, "\"; Shiny doesn't use them"
      )
    }

    # We don't support prependContent/appendContent in dynamic Shiny contexts
    # because the Shiny equivalent of onStaticRenderComplete is unclear. If we
    # ever figure that out it would be great to support it. One possibility
    # would be to have a dedicated property for "post-render customization JS",
    # I suppose. In any case, it's less of a big deal for Shiny since there are
    # other mechanisms (that are at least as natural) for putting custom JS in a
    # Shiny app.
    if (!is.null(instance$prepend)) {
      warning("Ignoring prepended content; prependContent can't be used in a ",
        "Shiny render call")
    }
    if (!is.null(instance$append)) {
      warning("Ignoring appended content; appendContent can't be used in a ",
        "Shiny render call")
    }

    deps <- .subset2(instance, "dependencies")
    deps <- lapply(
      htmltools::resolveDependencies(deps),
      shiny::createWebDependency
    )
    payload <- c(createPayload(instance), list(deps = deps))
    toJSON(payload)
  }

  # mark it with the output function so we can use it in Rmd files
  shiny::markRenderFunction(outputFunction, renderFunc)
}

checkShinyVersion <- function(error = TRUE) {
  x <- utils::packageDescription('htmlwidgets', fields = 'Enhances')
  r <- '^.*?shiny \\(>= ([0-9.]+)\\).*$'
  if (is.na(x) || length(grep(r, x)) == 0 || system.file(package = 'shiny') == '')
    return()
  v <- gsub(r, '\\1', x)
  f <- if (error) stop else packageStartupMessage
  if (utils::packageVersion('shiny') < v)
    f("Please upgrade the 'shiny' package to (at least) version ", v)
}

# Helper function to create payload
createPayload <- function(instance){
  if (!is.null(instance$preRenderHook)){
    instance <- instance$preRenderHook(instance)
    instance$preRenderHook <- NULL
  }
  x <- .subset2(instance, "x")
  list(x = x, evals = JSEvals(x), jsHooks = instance$jsHooks)
}

# package globals
.globals <- new.env(parent = emptyenv())

