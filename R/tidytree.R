##' @importFrom ggplot2 fortify
##' @method fortify treedata
##' @export
fortify.treedata <- function(model, data, layout="rectangular", branch.length ="branch.length",
                             ladderize=TRUE, right=FALSE, mrsd=NULL, ...) {
    model <- set_branch_length(model, branch.length)
    
    x <- reorder.phylo(get.tree(model), "postorder")
    if (is.null(x$edge.length) || branch.length == "none") {
        xpos <- getXcoord_no_length(x)
    } else {
        xpos <- getXcoord(x)
    }
    ypos <- getYcoord(x)
    N <- Nnode(x, internal.only=FALSE)
    xypos <- data.frame(node=1:N, x=xpos, y=ypos)

    df <- as.data.frame(model, branch.length="branch.length") # already set by set_branch_length
    idx <- is.na(df$parent)
    df$parent[idx] <- df$node[idx]
    rownames(df) <- df$node

    res <- merge(df, xypos, by='node', all.y=TRUE)

    ## add branch mid position
    res <- calculate_branch_mid(res)

    ## ## angle for all layout, if 'rectangular', user use coord_polar, can still use angle
    res <- calculate_angle(res)
    res
}

##' @method as.data.frame treedata
##' @export
## @importFrom treeio Nnode
## @importFrom treeio Ntip
as.data.frame.treedata <- function(x, row.names, optional, branch.length = "branch.length", ...) {
    tree <- set_branch_length(x, branch.length)

    ## res <- as.data.frame(tree@phylo)
    res <- as.data.frame_(tree@phylo)
    tree_anno <- get_tree_data(x)
    if (nrow(tree_anno) > 0) {
        res <- merge(res, tree_anno, by="node", all.x=TRUE)
    }
    return(res)
}

##@method as.data.frame phylo
##@export
as.data.frame_ <- function(x, row.names, optional, branch.length = "branch.length", ...) {
    phylo <- x
    ntip <- Ntip(phylo)
    N <- Nnode(phylo, internal.only=FALSE)

    tip.label <- phylo[["tip.label"]]
    res <- as.data.frame(phylo[["edge"]])
    colnames(res) <- c("parent", "node")
    if (!is.null(phylo$edge.length))
        res$branch.length <- phylo$edge.length

    label <- rep(NA, N)
    label[1:ntip] <- tip.label
    if ( !is.null(phylo$node.label) ) {
        label[(ntip+1):N] <- phylo$node.label
    }
    label.df <- data.frame(node=1:N, label=label)
    res <- merge(res, label.df, by='node', all.y=TRUE)
    isTip <- rep(FALSE, N)
    isTip[1:ntip] <- TRUE
    res$isTip <- isTip

    return(res)
}

get_tree_data <- function(tree_object) {
    tree_anno <- tree_object@data
    if (has.extraInfo(tree_object)) {
        if (nrow(tree_anno) > 0) {
            tree_anno <- merge(tree_anno, tree_object@extraInfo, by="node")
        } else {
            return(tree_object@extraInfo)
        }
    }
    return(tree_anno)
}


##' convert tip or node label(s) to internal node number
##'
##'
##' @title nodeid
##' @param x tree object or graphic object return by ggtree
##' @param label tip or node label(s)
##' @return internal node number
##' @export
##' @author Guangchuang Yu
nodeid <- function(x, label) {
    if (is(x, "gg"))
        return(nodeid.gg(x, label))

    nodeid.tree(x, label)
}

nodeid.tree <- function(tree, label) {
    tr <- get.tree(tree)
    lab <- c(tr$tip.label, tr$node.label)
    match(label, lab)
}

nodeid.gg <- function(p, label) {
    p$data$node[match(label, p$data$label)]
}


reroot_node_mapping <- function(tree, tree2) {
    root <- getRoot(tree)

    node_map <- data.frame(from=1:getNodeNum(tree), to=NA, visited=FALSE)
    node_map[1:Ntip(tree), 2] <- match(tree$tip.label, tree2$tip.label)
    node_map[1:Ntip(tree), 3] <- TRUE

    node_map[root, 2] <- root
    node_map[root, 3] <- TRUE

    node <- rev(tree$edge[,2])
    for (k in node) {
        ip <- getParent(tree, k)
        if (node_map[ip, "visited"])
            next

        cc <- getChild(tree, ip)
        node2 <- node_map[cc,2]
        if (anyNA(node2)) {
            node <- c(node, k)
            next
        }

        to <- unique(sapply(node2, getParent, tr=tree2))
        to <- to[! to %in% node_map[,2]]
        node_map[ip, 2] <- to
        node_map[ip, 3] <- TRUE
    }
    node_map <- node_map[, -3]
    return(node_map)
}



##' @importFrom ape reorder.phylo
layout.unrooted <- function(tree) {
    N <- getNodeNum(tree)
    root <- getRoot(tree)

    df <- as.data.frame.phylo_(tree)
    df$x <- NA
    df$y <- NA
    df$start <- NA
    df$end   <- NA
    df$angle <- NA
    df[root, "x"] <- 0
    df[root, "y"] <- 0
    df[root, "start"] <- 0
    df[root, "end"]   <- 2
    df[root, "angle"] <- 0

    nb.sp <- sapply(1:N, function(i) length(get.offspring.tip(tree, i)))

    nodes <- getNodes_by_postorder(tree)

    for(curNode in nodes) {
        curNtip <- nb.sp[curNode]
        children <- getChild(tree, curNode)

        start <- df[curNode, "start"]
        end <- df[curNode, "end"]

        if (length(children) == 0) {
            ## is a tip
            next
        }

        for (i in seq_along(children)) {
            child <- children[i]
            ntip.child <- nb.sp[child]

            alpha <- (end - start) * ntip.child/curNtip
            beta <- start + alpha / 2

            length.child <- df[child, "length"]
            df[child, "x"] <- df[curNode, "x"] + cospi(beta) * length.child
            df[child, "y"] <- df[curNode, "y"] + sinpi(beta) * length.child
            df[child, "angle"] <- -90 -180 * beta * sign(beta - 1)
            df[child, "start"] <- start
            df[child, "end"] <- start + alpha
            start <- start + alpha
        }

    }

    return(df)
}

getParent.df <- function(df, node) {
    i <- which(df$node == node)
    res <- df$parent[i]
    if (res == node) {
        ## root node
        return(0)
    }
    return(res)
}

getAncestor.df <- function(df, node) {
    anc <- getParent.df(df, node)
    anc <- anc[anc != 0]
    if (length(anc) == 0) {
        stop("selected node is root...")
    }
    i <- 1
    while(i<= length(anc)) {
        anc <- c(anc, getParent.df(df, anc[i]))
        anc <- anc[anc != 0]
        i <- i+1
    }
    return(anc)
}


getChild.df <- function(df, node) {
    i <- which(df$parent == node)
    if (length(i) == 0) {
        return(0)
    }
    res <- df[i, "node"]
    res <- res[res != node] ## node may root
    return(res)
}

get.offspring.df <- function(df, node) {
    sp <- getChild.df(df, node)
    sp <- sp[sp != 0]
    if (length(sp) == 0) {
        stop("input node is a tip...")
    }

    i <- 1
    while(i <= length(sp)) {
        sp <- c(sp, getChild.df(df, sp[i]))
        sp <- sp[sp != 0]
        i <- i + 1
    }
    return(sp)
}


##' extract offspring tips
##'
##'
##' @title get.offspring.tip
##' @param tr tree
##' @param node node
##' @return tip label
##' @author ygc
##' @importFrom ape extract.clade
##' @export
get.offspring.tip <- function(tr, node) {
    if ( ! node %in% tr$edge[,1]) {
        ## return itself
        return(tr$tip.label[node])
    }
    clade <- extract.clade(tr, node)
    clade$tip.label
}


## ##' calculate total number of nodes
## ##'
## ##'
## ##' @title getNodeNum
## ##' @param tr phylo object
## ##' @return number
## ##' @author Guangchuang Yu
## ##' @export
## getNodeNum <- function(tr) {
##     Ntip <- length(tr[["tip.label"]])
##     Nnode <- tr[["Nnode"]]
##     ## total nodes
##     N <- Ntip + Nnode
##     return(N)
## }

getParent <- function(tr, node) {
    if ( node == getRoot(tr) )
        return(0)
    edge <- tr[["edge"]]
    parent <- edge[,1]
    child <- edge[,2]
    res <- parent[child == node]
    if (length(res) == 0) {
        stop("cannot found parent node...")
    }
    if (length(res) > 1) {
        stop("multiple parent found...")
    }
    return(res)
}

getChild <- function(tr, node) {
    edge <- tr[["edge"]]
    res <- edge[edge[,1] == node, 2]
    ## if (length(res) == 0) {
    ##     ## is a tip
    ##     return(NA)
    ## }
    return(res)
}

getSibling <- function(tr, node) {
    root <- getRoot(tr)
    if (node == root) {
        return(NA)
    }

    parent <- getParent(tr, node)
    child <- getChild(tr, parent)
    sib <- child[child != node]
    return(sib)
}


getAncestor <- function(tr, node) {
    root <- getRoot(tr)
    if (node == root) {
        return(NA)
    }
    parent <- getParent(tr, node)
    res <- parent
    while(parent != root) {
        parent <- getParent(tr, parent)
        res <- c(res, parent)
    }
    return(res)
}

isRoot <- function(tr, node) {
    getRoot(tr) == node
}

getNodeName <- function(tr) {
    if (is.null(tr$node.label)) {
        n <- length(tr$tip.label)
        nl <- (n + 1):(2 * n - 2)
        nl <- as.character(nl)
    }
    else {
        nl <- tr$node.label
    }
    nodeName <- c(tr$tip.label, nl)
    return(nodeName)
}

## ##' get the root number
## ##'
## ##'
## ##' @title getRoot
## ##' @param tr phylo object
## ##' @return root number
## ##' @export
## ##' @author Guangchuang Yu
## getRoot <- function(tr) {
##     edge <- tr[["edge"]]
##     ## 1st col is parent,
##     ## 2nd col is child,
##     if (!is.null(attr(tr, "order")) && attr(tr, "order") == "postorder")
##         return(edge[nrow(edge), 1])

##     parent <- unique(edge[,1])
##     child <- unique(edge[,2])
##     ## the node that has no parent should be the root
##     root <- parent[ ! parent %in% child ]
##     if (length(root) > 1) {
##         stop("multiple roots founded...")
##     }
##     return(root)
## }

get.trunk <- function(tr) {
    root <- getRoot(tr)
    path_length <- sapply(1:(root-1), function(x) get.path_length(tr, root, x))
    i <- which.max(path_length)
    return(get.path(tr, root, i))
}

##' path from start node to end node
##'
##'
##' @title get.path
##' @param phylo phylo object
##' @param from start node
##' @param to end node
##' @return node vectot
##' @export
##' @author Guangchuang Yu
get.path <- function(phylo, from, to) {
    anc_from <- getAncestor(phylo, from)
    anc_from <- c(from, anc_from)
    anc_to <- getAncestor(phylo, to)
    anc_to <- c(to, anc_to)
    mrca <- intersect(anc_from, anc_to)[1]

    i <- which(anc_from == mrca)
    j <- which(anc_to == mrca)

    path <- c(anc_from[1:i], rev(anc_to[1:(j-1)]))
    return(path)
}

get.path_length <- function(phylo, from, to, weight=NULL) {
    path <- get.path(phylo, from, to)
    if (is.null(weight)) {
        return(length(path)-1)
    }

    df <- fortify(phylo)
    if ( ! (weight %in% colnames(df))) {
        stop("weight should be one of numerical attributes of the tree...")
    }

    res <- 0

    get_edge_index <- function(df, from, to) {
        which((df[,1] == from | df[,2] == from) &
                  (df[,1] == to | df[,2] == to))
    }

    for(i in 1:(length(path)-1)) {
        ee <- get_edge_index(df, path[i], path[i+1])
        res <- res + df[ee, weight]
    }

    return(res)
}

getNodes_by_postorder <- function(tree) {
    tree <- reorder.phylo(tree, "postorder")
    unique(rev(as.vector(t(tree$edge[,c(2,1)]))))
}

getXcoord2 <- function(x, root, parent, child, len, start=0, rev=FALSE) {
    x[root] <- start
    x[-root] <- NA  ## only root is set to start, by default 0

    currentNode <- root
    direction <- 1
    if (rev == TRUE) {
        direction <- -1
    }
    while(anyNA(x)) {
        idx <- which(parent %in% currentNode)
        newNode <- child[idx]
        x[newNode] <- x[parent[idx]]+len[idx] * direction
        currentNode <- newNode
    }

    return(x)
}

getXcoord_no_length <- function(tr) {
    edge <- tr$edge
    parent <- edge[,1]
    child <- edge[,2]
    root <- getRoot(tr)

    len <- tr$edge.length

    N <- getNodeNum(tr)
    x <- numeric(N)
    ntip <- Ntip(tr)
    currentNode <- 1:ntip
    x[-currentNode] <- NA

    cl <- split(child, parent)
    child_list <- list()
    child_list[as.numeric(names(cl))] <- cl

    while(anyNA(x)) {
        idx <- match(currentNode, child)
        pNode <- parent[idx]
        ## child number table
        p1 <- table(parent[parent %in% pNode])
        p2 <- table(pNode)
        np <- names(p2)
        i <- p1[np] == p2
        newNode <- as.numeric(np[i])

        exclude <- rep(NA, max(child))
        for (j in newNode) {
            x[j] <- min(x[child_list[[j]]]) - 1
            exclude[child_list[[j]]] <- child_list[[j]]
        }
        exclude <- exclude[!is.na(exclude)]

        ## currentNode %<>% `[`(!(. %in% exclude))
        ## currentNode %<>% c(., newNode) %>% unique
        currentNode <- currentNode[!currentNode %in% exclude]
        currentNode <- unique(c(currentNode, newNode))

    }
    x <- x - min(x)
    return(x)
}


getXcoord <- function(tr) {
    edge <- tr$edge
    parent <- edge[,1]
    child <- edge[,2]
    root <- getRoot(tr)

    len <- tr$edge.length

    N <- getNodeNum(tr)
    x <- numeric(N)
    x <- getXcoord2(x, root, parent, child, len)
    return(x)
}

getXYcoord_slanted <- function(tr) {

    edge <- tr$edge
    parent <- edge[,1]
    child <- edge[,2]
    root <- getRoot(tr)

    N <- getNodeNum(tr)
    len <- tr$edge.length
    y <- getYcoord(tr, step=min(len)/2)

    len <- sqrt(len^2 - (y[parent]-y[child])^2)
    x <- numeric(N)
    x <- getXcoord2(x, root, parent, child, len)
    res <- data.frame(x=x, y=y)
    return(res)
}


## @importFrom magrittr %>%
##' @importFrom magrittr equals
getYcoord <- function(tr, step=1) {
    Ntip <- length(tr[["tip.label"]])
    N <- getNodeNum(tr)

    edge <- tr[["edge"]]
    parent <- edge[,1]
    child <- edge[,2]

    cl <- split(child, parent)
    child_list <- list()
    child_list[as.numeric(names(cl))] <- cl

    y <- numeric(N)
    tip.idx <- child[child <= Ntip]
    y[tip.idx] <- 1:Ntip * step
    y[-tip.idx] <- NA

    currentNode <- 1:Ntip
    while(anyNA(y)) {
        pNode <- unique(parent[child %in% currentNode])
        ## piping of magrittr is slower than nested function call.
        ## pipeR is fastest, may consider to use pipeR
        ##
        ## child %in% currentNode %>% which %>% parent[.] %>% unique
        ## idx <- sapply(pNode, function(i) all(child[parent == i] %in% currentNode))
        idx <- sapply(pNode, function(i) all(child_list[[i]] %in% currentNode))
        newNode <- pNode[idx]

        y[newNode] <- sapply(newNode, function(i) {
            mean(y[child_list[[i]]], na.rm=TRUE)
            ##child[parent == i] %>% y[.] %>% mean(na.rm=TRUE)
        })

        currentNode <- c(currentNode[!currentNode %in% unlist(child_list[newNode])], newNode)
        ## currentNode <- c(currentNode[!currentNode %in% child[parent %in% newNode]], newNode)
        ## parent %in% newNode %>% child[.] %>%
        ##     `%in%`(currentNode, .) %>% `!` %>%
        ##         currentNode[.] %>% c(., newNode)
    }

    return(y)
}


getYcoord_scale <- function(tr, df, yscale) {

    N <- getNodeNum(tr)
    y <- numeric(N)

    root <- getRoot(tr)
    y[root] <- 0
    y[-root] <- NA

    edge <- tr$edge
    parent <- edge[,1]
    child <- edge[,2]

    currentNodes <- root
    while(anyNA(y)) {
        newNodes <- c()
        for (currentNode in currentNodes) {
            idx <- which(parent %in% currentNode)
            newNode <- child[idx]
            direction <- -1
            for (i in seq_along(newNode)) {
                y[newNode[i]] <- y[currentNode] + df[newNode[i], yscale] * direction
                direction <- -1 * direction
            }
            newNodes <- c(newNodes, newNode)
        }
        currentNodes <- unique(newNodes)
    }
    if (min(y) < 0) {
        y <- y + abs(min(y))
    }
    return(y)
}

getYcoord_scale2 <- function(tr, df, yscale) {
    root <- getRoot(tr)

    pathLength <- sapply(1:length(tr$tip.label), function(i) {
        get.path_length(tr, i, root, yscale)
    })

    ordered_tip <- order(pathLength, decreasing = TRUE)
    ii <- 1
    ntip <- length(ordered_tip)
    while(ii < ntip) {
        sib <- getSibling(tr, ordered_tip[ii])
        if (length(sib) == 0) {
            ii <- ii + 1
            next
        }
        jj <- which(ordered_tip %in% sib)
        if (length(jj) == 0) {
            ii <- ii + 1
            next
        }
        sib <- ordered_tip[jj]
        ordered_tip <- ordered_tip[-jj]
        nn <- length(sib)
        if (ii < length(ordered_tip)) {
            ordered_tip <- c(ordered_tip[1:ii],sib, ordered_tip[(ii+1):length(ordered_tip)])
        } else {
            ordered_tip <- c(ordered_tip[1:ii],sib)
        }

        ii <- ii + nn + 1
    }


    long_branch <- getAncestor(tr, ordered_tip[1]) %>% rev
    long_branch <- c(long_branch, ordered_tip[1])

    N <- getNodeNum(tr)
    y <- numeric(N)

    y[root] <- 0
    y[-root] <- NA

    ## yy <- df[, yscale]
    ## yy[is.na(yy)] <- 0

    for (i in 2:length(long_branch)) {
        y[long_branch[i]] <- y[long_branch[i-1]] + df[long_branch[i], yscale]
    }

    parent <- df[, "parent"]
    child <- df[, "node"]

    currentNodes <- root
    while(anyNA(y)) {
        newNodes <- c()
        for (currentNode in currentNodes) {
            idx <- which(parent %in% currentNode)
            newNode <- child[idx]
            newNode <- c(newNode[! newNode %in% ordered_tip],
                         rev(ordered_tip[ordered_tip %in% newNode]))
            direction <- -1
            for (i in seq_along(newNode)) {
                if (is.na(y[newNode[i]])) {
                    y[newNode[i]] <- y[currentNode] + df[newNode[i], yscale] * direction
                    direction <- -1 * direction
                }
            }
            newNodes <- c(newNodes, newNode)
        }
        currentNodes <- unique(newNodes)
    }
    if (min(y) < 0) {
        y <- y + abs(min(y))
    }
    return(y)
}

getYcoord_scale_numeric <- function(tr, df, yscale, ...) {
    df <- .assign_parent_status(tr, df, yscale)
    df <- .assign_child_status(tr, df, yscale)

    y <- df[, yscale]

    if (anyNA(y)) {
        warning("NA found in y scale mapping, all were setting to 0")
        y[is.na(y)] <- 0
    }

    return(y)
}

.assign_parent_status <- function(tr, df, variable) {
    yy <- df[, variable]
    na.idx <- which(is.na(yy))
    if (length(na.idx) > 0) {
        tree <- get.tree(tr)
        nodes <- getNodes_by_postorder(tree)
        for (curNode in nodes) {
            children <- getChild(tree, curNode)
            if (length(children) == 0) {
                next
            }
            idx <- which(is.na(yy[children]))
            if (length(idx) > 0) {
                yy[children[idx]] <- yy[curNode]
            }
        }
    }
    df[, variable] <- yy
    return(df)
}

.assign_child_status <- function(tr, df, variable, yscale_mapping=NULL) {
    yy <- df[, variable]
    if (!is.null(yscale_mapping)) {
        yy <- yscale_mapping[yy]
    }

    na.idx <- which(is.na(yy))
    if (length(na.idx) > 0) {
        tree <- get.tree(tr)
        nodes <- rev(getNodes_by_postorder(tree))
        for (curNode in nodes) {
            parent <- getParent(tree, curNode)
            if (parent == 0) { ## already reach root
                next
            }
            idx <- which(is.na(yy[parent]))
            if (length(idx) > 0) {
                child <- getChild(tree, parent)
                yy[parent[idx]] <- mean(yy[child], na.rm=TRUE)
            }
        }
    }
    df[, variable] <- yy
    return(df)
}


getYcoord_scale_category <- function(tr, df, yscale, yscale_mapping=NULL, ...) {
    if (is.null(yscale_mapping)) {
        stop("yscale is category variable, user should provide yscale_mapping,
             which is a named vector, to convert yscale to numberical values...")
    }
    if (! is(yscale_mapping, "numeric") ||
        is.null(names(yscale_mapping))) {
        stop("yscale_mapping should be a named numeric vector...")
    }

    if (yscale == "label") {
        yy <- df[, yscale]
        ii <- which(is.na(yy))
        if (length(ii)) {
            df[ii, yscale] <- df[ii, "node"]
        }
    }

    ## assign to parent status is more prefer...
    df <- .assign_parent_status(tr, df, yscale)
    df <- .assign_child_status(tr, df, yscale, yscale_mapping)

    y <- df[, yscale]

    if (anyNA(y)) {
        warning("NA found in y scale mapping, all were setting to 0")
        y[is.na(y)] <- 0
    }
    return(y)
}


add_angle_slanted <- function(res) {
    dy <- (res[, "y"] - res[res$parent, "y"]) / diff(range(res[, "y"]))
    dx <- (res[, "x"] - res[res$parent, "x"]) / diff(range(res[, "x"]))
    theta <- atan(dy/dx)
    theta[is.na(theta)] <- 0 ## root node
    res$angle <- theta/pi * 180
    branch.y <- (res[res$parent, "y"] + res[, "y"])/2
    idx <- is.na(branch.y)
    branch.y[idx] <- res[idx, "y"]
    res[, "branch.y"] <- branch.y
    return(res)
}

calculate_branch_mid <- function(res) {
    res$branch <- (res[res$parent, "x"] + res[, "x"])/2
    if (!is.null(res$length)) {
        res$length[is.na(res$length)] <- 0
    }
    res$branch[is.na(res$branch)] <- 0
    return(res)
}


set_branch_length <- function(tree_object, branch.length) {
    if (branch.length == "branch.length") {
        return(tree_object)
    } else if (branch.length == "none") {
        if (is(tree_object, "phylo4d")) {
            tree_object@edge.length <- NULL
        } else { 
            tree_object@phylo$edge.length <- NULL
        }
        return(tree_object)
    }

    if (is(tree_object, "phylo")) {
        return(tree_object)
    }

    if (is(tree_object, "phylo4d")) {
        phylo <- as.phylo.phylo4(tree_object)
        d <- tree_object@data
        tree_anno <- data.frame(node=rownames(d), d)
    } else if (is(tree_object, "codeml")) {
        tree_anno <- tree_object@mlc@dNdS
    } else if (is(tree_object, "codeml_mlc")) {
        tree_anno <- tree_object@dNdS
    } else if (is(tree_object, "beast")) {
        tree_anno <- tree_object@stats
    } else {
        tree_anno <- get_tree_data(tree_object)
    }

    if (!is(tree_object, "phylo4d")) {
        phylo <- get.tree(tree_object)
    }
    
    cn <- colnames(tree_anno)
    cn <- cn[!cn %in% c('node', 'parent')]

    length <- match.arg(branch.length, cn)

    if (all(is.na(as.numeric(tree_anno[, length])))) {
        stop("branch.length should be numerical attributes...")
    }

    edge <- as.data.frame(phylo$edge)
    colnames(edge) <- c("parent", "node")

    dd <- merge(edge, tree_anno,
                by  = "node",
                all.x = TRUE)
    dd <- dd[match(edge$node, dd$node),]
    len <- unlist(dd[, length])
    len <- as.numeric(len)
    len[is.na(len)] <- 0

    phylo$edge.length <- len

    if (is(tree_object, "phylo4d")) {
        tree_object@edge.length <- phylo$edge.length
    } else {
        tree_object@phylo <- phylo
    }
    return(tree_object)
}

## set_branch_length <- function(tree_object, branch.length) {
##     if (is(tree_object, "phylo4d")) {
##         phylo <- as.phylo.phylo4(tree_object)
##         d <- tree_object@data
##         tree_anno <- data.frame(node=rownames(d), d)
##     } else {
##         phylo <- get.tree(tree_object)
##     }

##     if (branch.length %in%  c("branch.length", "none")) {
##         return(phylo)
##     }

##     ## if (is(tree_object, "codeml")) {
##     ##     tree_anno <- tree_object@mlc@dNdS
##     ## } else

##     if (is(tree_object, "codeml_mlc")) {
##         tree_anno <- tree_object@dNdS
##     } else if (is(tree_object, "beast")) {
##         tree_anno <- tree_object@stats
##     }

##     if (has.extraInfo(tree_object)) {
##         tree_anno <- merge(tree_anno, tree_object@extraInfo, by.x="node", by.y="node")
##     }
##     cn <- colnames(tree_anno)
##     cn <- cn[!cn %in% c('node', 'parent')]

##     length <- match.arg(branch.length, cn)

##     if (all(is.na(as.numeric(tree_anno[, length])))) {
##         stop("branch.length should be numerical attributes...")
##     }

##     edge <- as.data.frame(phylo$edge)
##     colnames(edge) <- c("parent", "node")

##     dd <- merge(edge, tree_anno,
##                 by.x  = "node",
##                 by.y  = "node",
##                 all.x = TRUE)
##     dd <- dd[match(edge$node, dd$node),]
##     len <- unlist(dd[, length])
##     len <- as.numeric(len)
##     len[is.na(len)] <- 0

##     phylo$edge.length <- len

##     return(phylo)
## }


re_assign_ycoord_df <- function(df, currentNode) {
    while(anyNA(df$y)) {
        pNode <- with(df, parent[match(currentNode, node)]) %>% unique
        idx <- sapply(pNode, function(i) with(df, all(node[parent == i & parent != node] %in% currentNode)))
        newNode <- pNode[idx]
        ## newNode <- newNode[is.na(df[match(newNode, df$node), "y"])]

        df[match(newNode, df$node), "y"] <- sapply(newNode, function(i) {
            with(df, mean(y[parent == i], na.rm = TRUE))
        })
        traced_node <- as.vector(sapply(newNode, function(i) with(df, node[parent == i])))
        currentNode <- c(currentNode[! currentNode %in% traced_node], newNode)
    }
    return(df)
}


## ##' test whether input object is produced by ggtree function
## ##'
## ##'
## ##' @title is.ggtree
## ##' @param x object
## ##' @return TRUE or FALSE
## ##' @export
## ##' @author guangchuang yu
## is.ggtree <- function(x) inherits(x, 'ggtree')



calculate_angle <- function(data) {
    data$angle <- 360/(diff(range(data$y)) + 1) * data$y
    return(data)
}
